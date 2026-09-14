<?php

namespace App\Http\Controllers\Api;

use App\Domain\Allocation\LedgerService;
use App\Domain\Progress\BadgeService;
use App\Domain\Verification\Decision;
use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\Submission;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Parent-side review. Chapter 2 promises the parent may confirm, override or
 * reject ANY classification -- not only the uncertain ones -- so this accepts
 * automatically decided submissions too. Without that, an automatic approval
 * would never acquire ground truth and the false-approval rate in Chapter 4
 * would be uncomputable.
 */
class ReviewController extends Controller
{
    public function __construct(
        private readonly LedgerService $ledger,
        private readonly BadgeService $badges,
    ) {
    }

    /**
     * The queue. Defaults to what needs attention; ?scope=all shows
     * everything, which is how a parent audits automatic decisions.
     */
    public function index(Request $request): JsonResponse
    {
        $childIds = $request->user()->children()->pluck('id');

        $query = Submission::whereIn('child_id', $childIds)
            ->with(['assignment.template', 'child']);

        if ($request->query('scope') !== 'all') {
            $query->pending();
        }

        $submissions = $query->latest()->limit(100)->get();

        return response()->json([
            'submissions' => $submissions->map(function (Submission $s) {
                return SubmissionController::payloadFor($s) + [
                    'child_name' => $s->child->name,
                ];
            })->all(),
        ]);
    }

    public function decide(Request $request, Submission $submission): JsonResponse
    {
        $this->authoriseOwnership($request, $submission);

        $data = $request->validate([
            'decision' => ['required', 'in:approved,rejected'],
        ]);

        $approving = $data['decision'] === Decision::APPROVED;

        // One decision at a time per submission. Without the row lock, an
        // approval on one phone and a send-back on another can interleave so
        // that the status says one thing and the ledger the other.
        return DB::transaction(function () use ($request, $submission, $approving, $data) {
            $submission = Submission::whereKey($submission->id)->lockForUpdate()->firstOrFail();

            if ($approving && $this->ledger->hasBeenReversed($submission)) {
                return response()->json([
                    'message' => "This photo's screen time was already taken back once, "
                        . "so it can't be approved again. Ask for a new photo instead.",
                ], 409);
            }

            // routing and the model columns are deliberately untouched. Only the
            // parent's own columns move, so the machine's original verdict
            // survives to be measured against this one.
            $submission->update([
                'parent_decision' => $data['decision'],
                'parent_decided_at' => now(),
                'parent_user_id' => $request->user()->id,
                'status' => $approving ? Decision::APPROVED : Decision::REJECTED,
            ]);

            $submission->refresh()->load('assignment.template');

            // Approving credits the ledger; overturning an approval appends a
            // compensating entry rather than deleting the original.
            if ($approving) {
                $this->ledger->credit($submission);

                // Checked once the decision has committed, so a badge is never
                // awarded for an approval that did not stick.
                $childId = $submission->child_id;
                DB::afterCommit(function () use ($childId) {
                    $child = Child::find($childId);

                    if ($child) {
                        $this->badges->awardAfterApproval($child);
                    }
                });
            } else {
                $this->ledger->reverse($submission);
            }

            return response()->json([
                'submission' => SubmissionController::payloadFor($submission),
            ]);
        });
    }

    /**
     * Photographs of minors inside their homes. Never public: served only to
     * the parent who owns the household, and only through this route.
     */
    public function photo(Request $request, Submission $submission): StreamedResponse
    {
        $this->authoriseOwnership($request, $submission);

        abort_unless(Storage::disk('local')->exists($submission->photo_path), 404);

        return Storage::disk('local')->response($submission->photo_path);
    }

    private function authoriseOwnership(Request $request, Submission $submission): void
    {
        $owns = $request->user()->children()->whereKey($submission->child_id)->exists();

        abort_unless($owns, 404);
    }
}
