<?php

namespace App\Domain\Allocation;

/**
 * Converts a verified chore into released screen time.
 *
 * This is the deterministic half of the system, and it is deliberately a pure
 * function: no database, no clock, no randomness. Everything it needs is
 * passed in, so the same inputs always produce the same minutes and the
 * calculation can be exercised on its own without standing anything up.
 *
 * Cases handled, and the choice made in each:
 *
 *  1. Ordinary earning              released = points x minutes_per_point
 *  2. Daily cap reached             released is trimmed to what is left today
 *  3. Weekly cap reached            trimmed to what is left this week
 *  4. Both caps bite                the smaller remaining wins, and is named
 *  5. Chore worth more than the
 *     entire cap                    released = remaining, the rest forfeited
 *                                   and RECORDED, never silently dropped
 *  6. Cap already exceeded, e.g.
 *     a parent lowered it after
 *     minutes went out today        remaining clamps to 0, never negative.
 *                                   Minutes already released are not clawed
 *                                   back: taking back screen time a child has
 *                                   already been told they earned is exactly
 *                                   the inconsistency the study exists to fix.
 *  7. Zero-point chore              releases nothing, which is legal
 */
final class AllocationEngine
{
    public function compute(
        int $points,
        int $minutesPerPoint,
        int $dailyCapMinutes,
        int $weeklyCapMinutes,
        int $alreadyEarnedToday,
        int $alreadyEarnedThisWeek,
    ): Allocation {
        $gross = max(0, $points) * max(0, $minutesPerPoint);

        // Clamped at zero: a cap lowered below what has already gone out
        // leaves nothing further to give, but never a debt.
        $dailyRemaining = max(0, $dailyCapMinutes - $alreadyEarnedToday);
        $weeklyRemaining = max(0, $weeklyCapMinutes - $alreadyEarnedThisWeek);

        $released = min($gross, $dailyRemaining, $weeklyRemaining);
        $forfeited = $gross - $released;

        $cappedBy = null;
        if ($forfeited > 0) {
            // Name whichever limit actually bound. When both bind equally the
            // weekly one is reported, since it is the harder to notice.
            $cappedBy = $weeklyRemaining <= $dailyRemaining ? 'weekly' : 'daily';
        }

        return new Allocation(
            points: $points,
            grossMinutes: $gross,
            releasedMinutes: $released,
            forfeitedMinutes: $forfeited,
            dailyRemainingBefore: $dailyRemaining,
            weeklyRemainingBefore: $weeklyRemaining,
            cappedBy: $cappedBy,
        );
    }
}
