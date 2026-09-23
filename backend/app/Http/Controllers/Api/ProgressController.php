<?php

namespace App\Http\Controllers\Api;

use App\Domain\Allocation\LedgerService;
use App\Domain\Progress\BadgeService;
use App\Domain\Progress\ProgressService;
use App\Http\Controllers\Controller;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The child's game progress. Read-only: nothing a child or parent does here
 * changes it; it follows from approvals.
 */
class ProgressController extends Controller
{
    public function __construct(
        private readonly ProgressService $progress,
        private readonly BadgeService $badges,
    ) {
    }

    public function mine(Request $request): JsonResponse
    {
        $child = $request->user();
        $today = $child->localNow()->toDateString();
        $xp = $this->progress->xp($child);
        $stats = $this->progress->badgeStats($child);
        $streak = $this->progress->streak($child, $today);

        return response()->json([
            // The household's date, which submissions and streaks count in.
            'today' => $today,
            'xp' => $xp,
            // Approved quests, whatever their difficulty; badges count these.
            'quests' => $stats->quests,
            'streak' => $streak,
            'badges' => $this->badges->statusFor($child, $stats),
            'history' => $this->progress->history($child, $today),
        ]);
    }

    /**
     * One child's figures for the parent's Activity tab (ACT1), all in one
     * answer so that switching children changes every figure together:
     * completion over the last week, streak, XP and quests, and minutes
     * earned this week, read exactly as the child's own wallet reads them.
     */
    public function activity(Request $request, Child $child, LedgerService $ledger): JsonResponse
    {
        abort_unless($child->user_id === $request->user()->id, 404);

        $now = $child->localNow();
        $today = $now->toDateString();
        $rule = $child->rule();

        return response()->json([
            'child' => ['id' => $child->id, 'name' => $child->name, 'avatar' => $child->avatar],
            'today' => $today,
            'xp' => $this->progress->xp($child),
            'quests' => $this->progress->questCount($child),
            'streak' => $this->progress->streak($child, $today),
            'completion' => $this->progress->completion($child, $today),
            'earned_today' => $ledger->earnedOn($child, $now),
            'earned_this_week' => $ledger->earnedInWeekOf($child, $now),
            'daily_cap_minutes' => $rule->daily_cap_minutes,
            'weekly_cap_minutes' => $rule->weekly_cap_minutes,
        ]);
    }
}
