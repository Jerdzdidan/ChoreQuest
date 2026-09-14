<?php

namespace App\Domain\Progress;

use App\Domain\Verification\Decision;
use App\Models\Child;
use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;

/**
 * A child's game progress, derived on every read from submissions that
 * already exist.
 *
 * Nothing here is stored and nothing here touches screen time. XP is a count
 * of approved photos, not a balance: the ledger stays the only record of
 * minutes earned, so progress can never become a second source of truth.
 */
class ProgressService
{
    public function __construct(private readonly StreakCalculator $streaks)
    {
    }

    /**
     * One XP for every approved submission. Counted afresh each time, so a
     * parent overturning an approval takes that XP back with it.
     */
    public function xp(Child $child): int
    {
        return $child->submissions()
            ->where('status', Decision::APPROVED)
            ->count();
    }

    /**
     * The days that hold at least one approved quest, as Y-m-d strings.
     *
     * A photo counts for its for_date, the day it was sent, even when a
     * grown-up approves it later. Approving yesterday's photo this morning
     * therefore completes yesterday, never today.
     *
     * @return list<string>
     */
    public function approvedDays(Child $child): array
    {
        return $child->submissions()
            ->where('status', Decision::APPROVED)
            ->distinct()
            ->pluck('for_date')
            ->map(fn ($date) => $date instanceof DateTimeInterface
                ? $date->format('Y-m-d')
                : substr((string) $date, 0, 10))
            ->unique()
            ->values()
            ->all();
    }

    /**
     * XP earned on each of the last $days days, up to and including $today,
     * oldest first. Days with none are listed with 0, so a chart can draw
     * every day.
     *
     * @return list<array{date: string, xp: int}>
     */
    public function history(Child $child, string $today, int $days = 14): array
    {
        $end = new DateTimeImmutable($today, new DateTimeZone('UTC'));
        $start = $end->modify('-'.($days - 1).' days');

        $counts = $child->submissions()
            ->toBase()
            ->where('status', Decision::APPROVED)
            ->whereBetween('for_date', [$start->format('Y-m-d'), $end->format('Y-m-d')])
            ->selectRaw('for_date, COUNT(*) AS xp')
            ->groupBy('for_date')
            ->pluck('xp', 'for_date');

        $history = [];

        for ($day = $start; $day <= $end; $day = $day->modify('+1 day')) {
            $date = $day->format('Y-m-d');
            $history[] = ['date' => $date, 'xp' => (int) ($counts[$date] ?? 0)];
        }

        return $history;
    }

    public function longestStreak(Child $child): int
    {
        return $this->streaks->longest($this->approvedDays($child));
    }

    /**
     * @return array{current: int, best: int, today_counted: bool}
     */
    public function streak(Child $child, string $today): array
    {
        $days = $this->approvedDays($child);

        return [
            'current' => $this->streaks->current($days, $today),
            'best' => $this->streaks->longest($days),
            // Whether today already has an approved quest, so the app can
            // show a streak that is still waiting for today's.
            'today_counted' => in_array($today, $days, true),
        ];
    }
}
