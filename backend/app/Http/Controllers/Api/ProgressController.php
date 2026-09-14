<?php

namespace App\Http\Controllers\Api;

use App\Domain\Progress\BadgeService;
use App\Domain\Progress\ProgressService;
use App\Http\Controllers\Controller;
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
        $today = now()->toDateString();
        $xp = $this->progress->xp($child);
        $streak = $this->progress->streak($child, $today);

        return response()->json([
            // The server's date, which submissions and streaks count in.
            'today' => $today,
            'xp' => $xp,
            'streak' => $streak,
            'badges' => $this->badges->statusFor($child, $xp, $streak['best']),
            'history' => $this->progress->history($child, $today),
        ]);
    }
}
