<?php

namespace App\Domain\Progress;

use App\Domain\Verification\Decision;
use App\Models\Child;
use App\Models\User;
use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A child's game progress, derived on every read from submissions that
 * already exist.
 *
 * Nothing here is stored and nothing here touches screen time. XP is summed
 * from approved photos, not kept as a balance: the ledger stays the only
 * record of minutes earned, so progress can never become a second source of
 * truth.
 */
class ProgressService
{
    public function __construct(private readonly StreakCalculator $streaks)
    {
    }

    /**
     * The XP of every approved submission, each by its chore's difficulty
     * (Difficulty::xp). Summed afresh on every read, so a parent overturning
     * an approval takes that quest's XP back with it.
     *
     * A chore's difficulty is read as it is now, so re-tiering a catalogue
     * chore re-prices past quests too. Nothing is stored to go stale.
     */
    public function xp(Child $child): int
    {
        return (int) $this->approvedWithDifficulty($child)
            ->selectRaw($this->xpExpression().' AS xp')
            ->value('xp');
    }

    /**
     * How many quests have been approved, whatever their difficulty. Badges
     * such as 25 quests count quests, not XP.
     */
    public function questCount(Child $child): int
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

        $counts = $this->approvedWithDifficulty($child)
            ->whereBetween('submissions.for_date', [$start->format('Y-m-d'), $end->format('Y-m-d')])
            ->selectRaw('submissions.for_date AS day, '.$this->xpExpression().' AS xp')
            ->groupBy('submissions.for_date')
            ->pluck('xp', 'day')
            ->mapWithKeys(fn ($xp, $day) => [substr((string) $day, 0, 10) => (int) $xp]);

        $history = [];

        for ($day = $start; $day <= $end; $day = $day->modify('+1 day')) {
            $date = $day->format('Y-m-d');
            $history[] = ['date' => $date, 'xp' => (int) ($counts[$date] ?? 0)];
        }

        return $history;
    }

    /**
     * Everything the badges measure, from this child's approved quests.
     *
     * One query, then pure arithmetic in BadgeStats, which also reads each
     * quest's time of day in the household's timezone.
     */
    public function badgeStats(Child $child): BadgeStats
    {
        $rows = DB::table('submissions')
            ->join('assignments', 'assignments.id', '=', 'submissions.assignment_id')
            ->where('submissions.child_id', $child->id)
            ->where('submissions.status', Decision::APPROVED)
            ->orderBy('submissions.id')
            ->get(['submissions.for_date', 'submissions.created_at', 'assignments.location'])
            ->map(fn ($row) => [
                'for_date' => (string) $row->for_date,
                'created_at' => (string) $row->created_at,
                'location' => (string) ($row->location ?? 'other'),
            ])
            ->all();

        return BadgeStats::fromRows(
            $rows,
            $child->parent?->timezone ?: User::DEFAULT_TIMEZONE,
            $this->longestStreak($child),
            $this->familyContributions($child),
        );
    }

    /**
     * Approved quests this child contributed to a family boss quest. The
     * table arrives with F1; until then nobody has contributed to one.
     */
    private function familyContributions(Child $child): int
    {
        if (! Schema::hasTable('family_quest_contributions')) {
            return 0;
        }

        return DB::table('family_quest_contributions')->where('child_id', $child->id)->count();
    }

    /**
     * A child's approved submissions joined to their chore's difficulty.
     */
    private function approvedWithDifficulty(Child $child): Builder
    {
        return DB::table('submissions')
            ->join('assignments', 'assignments.id', '=', 'submissions.assignment_id')
            ->join('chore_templates', 'chore_templates.id', '=', 'assignments.chore_template_id')
            ->where('submissions.child_id', $child->id)
            ->where('submissions.status', Decision::APPROVED);
    }

    /**
     * SUM of each row's difficulty XP, built from the Difficulty enum so the
     * numbers are never repeated here.
     */
    private function xpExpression(): string
    {
        $whens = collect(Difficulty::cases())
            ->map(fn (Difficulty $d) => "WHEN '{$d->value}' THEN {$d->xp()}")
            ->implode(' ');

        return "COALESCE(SUM(CASE chore_templates.difficulty {$whens} ELSE 0 END), 0)";
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
