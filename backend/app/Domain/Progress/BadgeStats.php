<?php

namespace App\Domain\Progress;

use DateTimeImmutable;
use DateTimeZone;

/**
 * Everything the badges measure, worked out from a child's approved quests.
 *
 * Pure, like the allocation engine and the streak calculator: the rows and the
 * household's timezone are passed in, nothing is read from the clock or the
 * database, so any set of quests can be checked by hand.
 *
 * Days are the household's days (TZ3): for_date is already its local date, and
 * a quest's time of day is its created_at read in that timezone.
 */
final class BadgeStats
{
    /**
     * @param  array<string, int>  $questsByLocation
     */
    public function __construct(
        public readonly int $quests = 0,
        public readonly int $longestStreak = 0,
        public readonly array $questsByLocation = [],
        public readonly int $earlyBirdQuests = 0,
        public readonly int $weekendPairs = 0,
        public readonly int $perfectWeeks = 0,
        public readonly int $bestDay = 0,
        public readonly int $familyContributions = 0,
    ) {
    }

    /**
     * @param  list<array{for_date: string, created_at: string, location: string}>  $rows  approved quests
     */
    public static function fromRows(array $rows, string $timezone, int $longestStreak, int $familyContributions = 0): self
    {
        $zone = new DateTimeZone($timezone);
        $byLocation = [];
        $byDay = [];
        $early = 0;
        $weekdays = [];

        foreach ($rows as $row) {
            $date = substr($row['for_date'], 0, 10);
            $byDay[$date] = ($byDay[$date] ?? 0) + 1;

            $location = $row['location'] !== '' ? $row['location'] : 'other';
            $byLocation[$location] = ($byLocation[$location] ?? 0) + 1;

            // Before 9am where the household lives, not on the server's clock.
            $sentAt = (new DateTimeImmutable($row['created_at'], new DateTimeZone('UTC')))->setTimezone($zone);
            if ((int) $sentAt->format('G') < 9) {
                $early++;
            }

            $weekdays[(int) (new DateTimeImmutable($date))->format('N')] = true;
        }

        return new self(
            quests: count($rows),
            longestStreak: $longestStreak,
            questsByLocation: $byLocation,
            earlyBirdQuests: $early,
            // Saturday and Sunday both covered, though not necessarily the
            // same weekend: a child who does chores on any Saturday and any
            // Sunday has shown the habit the badge is about.
            weekendPairs: isset($weekdays[6]) && isset($weekdays[7]) ? 1 : 0,
            perfectWeeks: self::perfectWeeks(array_keys($byDay)),
            bestDay: $byDay === [] ? 0 : max($byDay),
            familyContributions: $familyContributions,
        );
    }

    /**
     * Calendar weeks, Monday to Sunday, with a quest on all seven days. A full
     * week rather than any seven days in a row, which is what the 7-day streak
     * badge already rewards.
     *
     * @param  list<string>  $days  Y-m-d, each with at least one approved quest
     */
    private static function perfectWeeks(array $days): int
    {
        $weeks = [];

        foreach ($days as $day) {
            $date = new DateTimeImmutable($day);
            $weeks[$date->format('o-W')][$date->format('N')] = true;
        }

        return count(array_filter($weeks, fn (array $daysInWeek) => count($daysInWeek) === 7));
    }

    public function questsIn(string $location): int
    {
        return $this->questsByLocation[$location] ?? 0;
    }
}
