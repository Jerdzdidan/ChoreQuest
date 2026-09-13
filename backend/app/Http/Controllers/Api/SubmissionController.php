<?php

namespace App\Http\Controllers\Api;

use App\Domain\Allocation\LedgerService;
use App\Domain\Verification\ConfidenceRouter;
use App\Domain\Verification\Decision;
use App\Http\Controllers\Controller;
use App\Models\Assignment;
use App\Models\Submission;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * Child-side intake: a photograph plus whatever the on-device model made of it.
 */
class SubmissionController extends Controller
{
    public function __construct(
        private readonly ConfidenceRouter $router,
        private readonly LedgerService $ledger,
    ) {
    }

    public function store(Request $request): JsonResponse
    {
        $child = $request->user();

        $data = $request->validate([
            'assignment_id' => ['required', 'integer'],
            'photo' => ['required', 'image', 'max:8192'],

            // Supplied by the device. Null until Phase 5 ships a real model,
            // and null thereafter for any chore with no trained class.
            'label' => ['nullable', 'in:done,not_done'],
            'confidence' => ['nullable', 'numeric', 'between:0,1'],
            'model_version' => ['nullable', 'string', 'max:40'],
            'inference_ms' => ['nullable', 'integer', 'min:0'],

            // Idempotency key for the offline queue in slice 3.5.
            'client_token' => ['nullable', 'uuid'],
        ]);

        // A replayed upload returns the original rather than creating a twin.
        if (! empty($data['client_token'])) {
            $existing = Submission::where('client_token', $data['client_token'])->first();
            if ($existing) {
                return response()->json(['submission' => $this->payload($existing), 'duplicate' => true], 200);
            }
        }

        $assignment = $child->assignments()->with('template')->find($data['assignment_id']);
        abort_unless($assignment, 404);

        $today = now()->toDateString();

        // One approved submission per chore per day. Retrying after a
        // rejection is allowed and expected; earning twice for the same chore
        // on the same day is not.
        $alreadyDone = $child->submissions()
            ->where('assignment_id', $assignment->id)
            ->whereDate('for_date', $today)
            ->where('status', Decision::APPROVED)
            ->exists();

        if ($alreadyDone) {
            throw ValidationException::withMessages([
                'assignment_id' => ['You have already finished this chore today.'],
            ]);
        }

        // A chore with no trained class never gets an automatic verdict, no
        // matter what the device sends. The catalogue flag decides this, not
        // the client, so a tampered app cannot buy itself an auto-approval.
        $modelVerifiable = $assignment->template->isModelVerifiable();
        $label = $modelVerifiable ? ($data['label'] ?? null) : null;
        $confidence = $modelVerifiable ? ($data['confidence'] ?? null) : null;

        $rule = $child->rule();
        $routing = $this->router->route($label, $confidence, $rule->confidence_high, $rule->confidence_low);

        $path = $request->file('photo')->store("submissions/{$child->id}", 'local');

        $submission = $child->submissions()->create([
            'assignment_id' => $assignment->id,
            'photo_path' => $path,
            'model_label' => $label,
            'model_confidence' => $confidence,
            'model_version' => $modelVerifiable ? ($data['model_version'] ?? null) : null,
            'inference_ms' => $data['inference_ms'] ?? null,
            'routing' => $routing,
            'status' => $this->router->statusFor($routing),
            'for_date' => $today,
            'client_token' => $data['client_token'] ?? null,
        ]);

        // An automatic approval releases screen time immediately. Anything
        // else waits for a person.
        if ($submission->isApproved()) {
            $submission->setRelation('assignment', $assignment);
            $this->ledger->credit($submission);
        }

        return response()->json(['submission' => $this->payload($submission)], 201);
    }

    /**
     * The child's own history. Scoped by the token, so it can only be theirs.
     */
    public function mine(Request $request): JsonResponse
    {
        $submissions = $request->user()->submissions()
            ->with('assignment.template')
            ->latest()
            ->limit(50)
            ->get();

        return response()->json([
            'submissions' => $submissions->map(fn (Submission $s) => $this->payload($s))->all(),
        ]);
    }

    public static function payloadFor(Submission $s): array
    {
        return [
            'id' => $s->id,
            'child_id' => $s->child_id,
            'assignment_id' => $s->assignment_id,
            'chore' => $s->relationLoaded('assignment') && $s->assignment?->relationLoaded('template')
                ? $s->assignment->template->name
                : null,
            'model_label' => $s->model_label,
            'model_confidence' => $s->model_confidence,
            'model_version' => $s->model_version,
            'inference_ms' => $s->inference_ms,
            'routing' => $s->routing,
            'parent_decision' => $s->parent_decision,
            'parent_decided_at' => $s->parent_decided_at?->toIso8601String(),
            'was_overridden' => $s->wasOverridden(),
            'status' => $s->status,
            'for_date' => $s->for_date->toDateString(),
            'photo_url' => url("/api/submissions/{$s->id}/photo"),
            'submitted_at' => $s->created_at->toIso8601String(),
        ];
    }

    private function payload(Submission $s): array
    {
        return self::payloadFor($s);
    }
}
