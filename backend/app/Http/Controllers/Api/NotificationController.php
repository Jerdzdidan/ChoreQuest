<?php

namespace App\Http\Controllers\Api;

use App\Domain\Verification\Routing;
use App\Http\Controllers\Controller;
use App\Models\Submission;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The parent's notification feed: one entry for every photo their children
 * send, newest first.
 *
 * A read over submissions rather than a table of its own, so each submission
 * is exactly one notification by construction and nothing can drift out of
 * step. Priority is the photo checker's own routing decision
 * (ConfidenceRouter), read as it was stored, never recomputed:
 *
 * - review: the checker was unsure and sent it to a grown-up;
 * - approved: the checker approved it on its own;
 * - sent_back: the checker sent it back on its own.
 *
 * Whether it still waits for a grown-up is its status, sent alongside.
 */
class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $parent = $request->user();
        $childIds = $parent->children()->pluck('id');
        $seenAt = $parent->notifications_seen_at;

        $submissions = Submission::whereIn('child_id', $childIds)
            ->with(['assignment.template', 'child'])
            ->latest('id')
            ->limit(100)
            ->get();

        $unread = Submission::whereIn('child_id', $childIds)
            ->when($seenAt, fn ($query) => $query->where('created_at', '>', $seenAt))
            ->count();

        return response()->json([
            'unread_count' => $unread,
            'notifications' => $submissions->map(fn (Submission $s) => SubmissionController::payloadFor($s) + [
                'child_name' => $s->child->name,
                'child_avatar' => $s->child->avatar,
                'priority' => $this->priorityOf($s),
                'unread' => $seenAt === null || $s->created_at->greaterThan($seenAt),
            ])->all(),
        ]);
    }

    /**
     * The parent opened the list: everything up to now has been seen.
     */
    public function seen(Request $request): JsonResponse
    {
        $parent = $request->user();
        $parent->forceFill(['notifications_seen_at' => now()])->save();

        return response()->json(['unread_count' => 0]);
    }

    private function priorityOf(Submission $s): string
    {
        return match ($s->routing) {
            Routing::AUTO_APPROVED => 'approved',
            Routing::AUTO_REJECTED => 'sent_back',
            default => 'review',
        };
    }
}
