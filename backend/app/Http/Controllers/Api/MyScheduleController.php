<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Assignment;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * GET /my/schedule (BE-7), child only: everything the phone needs to arm its
 * alarms with no further request, kept on the phone so it works offline
 * (DV-2, DV-3).
 *
 * Every active daily assignment, whatever its weekdays, and every active
 * one-time assignment from the household's today on, each with its schedule
 * and its chore (verification mode, class and minimum time included); the
 * server's time; and the household's timezone and date, so the phone works
 * the next ring out on the household's clock (TZ1-TZ3).
 */
class MyScheduleController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();
        $now = $child->localNow();

        $assignments = $child->assignments()
            ->with('template')
            ->where('is_active', true)
            ->where(fn ($q) => $q
                ->where('recurrence', 'daily')
                ->orWhere(fn ($once) => $once
                    ->where('recurrence', 'once')
                    ->whereDate('scheduled_date', '>=', $now->toDateString())))
            ->orderBy('id')
            ->get();

        return response()->json([
            'server_time' => now()->toIso8601String(),
            'timezone' => $now->timezoneName,
            'today' => $now->toDateString(),
            'assignments' => $assignments->map(fn (Assignment $a) => AssignmentController::payloadFor($a))->all(),
        ]);
    }
}
