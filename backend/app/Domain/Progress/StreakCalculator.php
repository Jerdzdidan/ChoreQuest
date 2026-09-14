<?php

namespace App\Domain\Progress;

use DateTimeImmutable;
use DateTimeZone;

/**
 * Streaks: runs of consecutive calendar days with at least one approved quest.
 *
 * A pure function, like the allocation engine: the days and "today" are passed
 * in, nothing is read from the clock or the database, so any sequence of dates
 * can be checked by hand.
 *
 * Days are plain Y-m-d dates, the server's for_date. Arithmetic runs in UTC
 * purely so that adding a day is always 24 hours; the dates themselves carry
 * no time of day.
 */
final class StreakCalculator
{
    /**
     * The streak as a child sees it right now.
     *
     * Today is not over, so a streak that reached yesterday still stands until
     * today ends without an approved quest. The first day with none after a
     * streak brings it to 0.
     *
     * @param  list<string>  $days  dates with at least one approved quest, any order
     * @param  string  $today  the server's date, Y-m-d
     */
    public function current(array $days, string $today): int
    {
        $set = array_flip($days);
        $cursor = $this->day($today);

        if (! isset($set[$cursor->format('Y-m-d')])) {
            $cursor = $cursor->modify('-1 day');
        }

        $count = 0;
        while (isset($set[$cursor->format('Y-m-d')])) {
            $count++;
            $cursor = $cursor->modify('-1 day');
        }

        return $count;
    }

    /**
     * The longest run ever, wherever it falls.
     *
     * @param  list<string>  $days
     */
    public function longest(array $days): int
    {
        $unique = array_values(array_unique($days));
        sort($unique);

        $best = 0;
        $run = 0;
        $previous = null;

        foreach ($unique as $date) {
            $day = $this->day($date);
            $run = $previous !== null && $previous->modify('+1 day') == $day ? $run + 1 : 1;
            $best = max($best, $run);
            $previous = $day;
        }

        return $best;
    }

    private function day(string $date): DateTimeImmutable
    {
        return new DateTimeImmutable(substr($date, 0, 10), new DateTimeZone('UTC'));
    }
}
