<?php

namespace App\Http\Controllers\Api;

use App\Domain\Verification\Decision;
use App\Domain\Verification\Evidence;
use App\Domain\Verification\Routing;
use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Submission;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * POST /quest-sessions (BE-2), child only: a finished live quest session,
 * Before and After photos and the evidence summary.
 *
 * Stored as one submission, the row XP, streaks, badges, family quests and
 * the ledger already read. It is always pending and its routing always
 * pending_review, the honest word for "waiting for a person": nothing is
 * credited here. Minutes follow only from a parent's approval
 * (ReviewController::decide), which is CLAUDE.md rule 3.
 */
class SessionController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'assignment_id' => ['required', 'integer'],
            'before' => ['required', 'image', 'max:8192'],
            'after' => ['required', 'image', 'max:8192'],
            'evidence' => ['required', 'string', 'max:'.Evidence::MAX_BYTES],
            'client_token' => ['required', 'uuid'],
        ]);

        // A replayed upload returns the original rather than creating a twin.
        $existing = Submission::where('client_token', $data['client_token'])->first();
        if ($existing) {
            abort_unless($existing->child_id === $child->id, 409);

            return response()->json(['submission' => SubmissionController::payloadFor($existing), 'duplicate' => true]);
        }

        $raw = json_decode($data['evidence'], true);
        if (! is_array($raw)) {
            throw ValidationException::withMessages(['evidence' => ['The evidence must be a JSON object.']]);
        }

        $assignment = $child->assignments()->with('template')->find($data['assignment_id']);
        abort_unless($assignment, 404);

        $today = $child->localNow()->toDateString();

        // One approved session per chore per day, as for photos before.
        $alreadyDone = $child->submissions()
            ->where('assignment_id', $assignment->id)
            ->whereDate('for_date', $today)
            ->where('status', Decision::APPROVED)
            ->exists();
        if ($alreadyDone) {
            throw ValidationException::withMessages([
                'assignment_id' => ['You have already finished this quest today.'],
            ]);
        }

        $evidence = Evidence::clean($raw);

        // The server decides whether the model's figures count, from the
        // catalogue, not from what the phone says: a custom or manual chore
        // is manual whatever arrives, and so is a session the model sat out.
        $motion = $assignment->template->isMotionChecked()
            && ($evidence['mode'] ?? null) === 'lstm'
            && ! ($evidence['model_unavailable'] ?? false);
        $mode = $motion ? Submission::MODE_LSTM : Submission::MODE_MANUAL;
        $evidence['mode'] = $mode;

        $folder = "submissions/{$child->id}";
        $before = $request->file('before')->store($folder, 'local');
        $after = $request->file('after')->store($folder, 'local');

        $submission = $child->submissions()->create([
            'assignment_id' => $assignment->id,
            'photo_path' => $after,
            'before_photo_path' => $before,
            // The model's columns carry its figures only for a movement-
            // checked chore; model_label names the chore it watched for.
            'model_label' => $motion ? $assignment->template->key : null,
            'model_confidence' => $motion ? ($evidence['mean_probability'] ?? null) : null,
            'model_version' => $motion ? ($evidence['model_version'] ?? null) : null,
            'inference_ms' => $motion ? ($evidence['mean_model_ms'] ?? null) : null,
            'evidence' => $evidence,
            'session_started_at' => $this->time($evidence['started_at'] ?? null),
            'session_done_at' => $this->time($evidence['finished_at'] ?? null),
            'active_seconds' => $motion ? ($evidence['active_seconds'] ?? null) : null,
            'verification_mode' => $mode,
            'camera_source' => $this->camera($evidence['camera'] ?? null),
            'routing' => Routing::PENDING_REVIEW,
            'status' => Decision::PENDING,
            'for_date' => $today,
            'client_token' => $data['client_token'],
        ]);

        $submission->setRelation('assignment', $assignment);

        return response()->json(['submission' => SubmissionController::payloadFor($submission)], 201);
    }

    /**
     * An ISO time from the phone, in UTC as every timestamp is stored, or
     * none when it cannot be read. Without the conversion a phone's
     * 09:00+08:00 would be stored as 09:00 UTC, eight hours late.
     */
    private function time(?string $raw): ?Carbon
    {
        if ($raw === null) {
            return null;
        }
        try {
            return Carbon::parse($raw)->utc();
        } catch (\Throwable) {
            return null;
        }
    }

    /** The camera as the assignments table names sources: phone or external. */
    private function camera(?string $raw): ?string
    {
        return match (true) {
            $raw === null => null,
            str_starts_with($raw, 'phone') => 'phone',
            default => 'external',
        };
    }
}
