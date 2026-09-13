<?php

namespace App\Domain\Allocation;

use App\Models\Child;
use App\Models\LedgerEntry;
use App\Models\Submission;
use Illuminate\Database\QueryException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Everything the engine deliberately does not do: reading the ledger, holding
 * a lock, and writing the result.
 *
 * The engine decides; this class arranges for it to decide on figures that
 * cannot change underneath it.
 */
class LedgerService
{
    /**
     * A week runs Monday to Sunday.
     *
     * A rolling seven-day window would be defensible arithmetically but not to
     * a child: earning less today than yesterday for the same chore has no
     * visible cause under a rolling window. A fixed boundary is predictable,
     * which is the property the study is actually claiming.
     */
    public const WEEK_STARTS_ON = Carbon::MONDAY;

    public function __construct(private readonly AllocationEngine $engine)
    {
    }

    /**
     * Credit an approved submission. Safe to call twice: the unique index on
     * (submission_id, entry_type) means a second attempt writes nothing and
     * the existing entry comes back instead.
     */
    public function credit(Submission $submission): ?LedgerEntry
    {
        return DB::transaction(function () use ($submission) {
            // Serialise allocation for this child. Without the lock, two
            // submissions approved at the same moment both read the same
            // remaining allowance and both release against it, quietly
            // exceeding the cap.
            $child = Child::whereKey($submission->child_id)->lockForUpdate()->firstOrFail();

            $existing = $this->entryFor($submission, LedgerEntry::EARNED);

            if ($existing) {
                return $existing;
            }

            $rule = $child->rule();
            $forDate = $submission->for_date;

            $allocation = $this->engine->compute(
                points: $submission->assignment->points,
                minutesPerPoint: $rule->minutes_per_point,
                dailyCapMinutes: $rule->daily_cap_minutes,
                weeklyCapMinutes: $rule->weekly_cap_minutes,
                alreadyEarnedToday: $this->earnedOn($child, $forDate),
                alreadyEarnedThisWeek: $this->earnedInWeekOf($child, $forDate),
            );

            try {
                return LedgerEntry::create([
                    'child_id' => $child->id,
                    'submission_id' => $submission->id,
                    'entry_type' => LedgerEntry::EARNED,
                    'minutes' => $allocation->releasedMinutes,
                    'points' => $allocation->points,
                    'minutes_gross' => $allocation->grossMinutes,
                    'minutes_forfeited' => $allocation->forfeitedMinutes,
                    'for_date' => $forDate,
                    'note' => $allocation->cappedBy
                        ? 'Trimmed by the ' . $allocation->cappedBy . ' limit'
                        : null,
                ]);
            } catch (QueryException) {
                // Lost a race to the unique index. The other writer's entry is
                // the correct one, so this call becomes a no-op.
                return $this->entryFor($submission, LedgerEntry::EARNED);
            }
        });
    }

    /**
     * Undo a credit after a parent overturns an approval.
     *
     * The original entry stays. A compensating entry is appended instead, so
     * the history still shows that minutes were granted and then withdrawn,
     * which is what a parent explaining the decision to a child needs.
     *
     * The reversal is for the full amount even when the child has already
     * spent it, so the balance can land below zero and is then worked off by
     * the next chore. Forgiving the shortfall would mean an overturned
     * approval sometimes costs nothing, and a child would learn that quickly.
     */
    public function reverse(Submission $submission, ?string $note = null): ?LedgerEntry
    {
        return DB::transaction(function () use ($submission, $note) {
            $child = Child::whereKey($submission->child_id)->lockForUpdate()->firstOrFail();

            $credit = $this->entryFor($submission, LedgerEntry::EARNED);

            if (! $credit || $credit->minutes === 0) {
                return null;
            }

            $already = $this->entryFor($submission, LedgerEntry::REVERSAL);

            if ($already) {
                return $already;
            }

            try {
                return LedgerEntry::create([
                    'child_id' => $child->id,
                    'submission_id' => $submission->id,
                    'entry_type' => LedgerEntry::REVERSAL,
                    'minutes' => -$credit->minutes,
                    'for_date' => $credit->for_date,
                    'note' => $note ?? 'A grown-up changed this to not finished',
                ]);
            } catch (QueryException) {
                return $this->entryFor($submission, LedgerEntry::REVERSAL);
            }
        });
    }

    /**
     * Whether this submission's earning has already been taken back.
     *
     * The unique index allows one earning and one reversal per submission, so
     * after a reversal a second approval could not credit the chore again: it
     * would mark the photo approved while its minutes stayed withdrawn. The
     * caller refuses that approval instead of recording it.
     */
    public function hasBeenReversed(Submission $submission): bool
    {
        return $this->entryFor($submission, LedgerEntry::REVERSAL) !== null;
    }

    /**
     * Spend screen time. Never takes the balance below zero, so a child cannot
     * spend minutes they do not have.
     */
    public function consume(Child $child, int $minutes, ?string $note = null): LedgerEntry
    {
        return DB::transaction(function () use ($child, $minutes, $note) {
            $locked = Child::whereKey($child->id)->lockForUpdate()->firstOrFail();

            $take = min(max(0, $minutes), max(0, $this->balance($locked)));

            return LedgerEntry::create([
                'child_id' => $locked->id,
                'entry_type' => LedgerEntry::CONSUMED,
                'minutes' => -$take,
                'for_date' => now()->toDateString(),
                'note' => $note,
            ]);
        });
    }

    public function balance(Child $child): int
    {
        return (int) LedgerEntry::where('child_id', $child->id)->sum('minutes');
    }

    /**
     * Only earnings count towards a cap.
     *
     * A reversal must not hand back cap headroom: if it did, an
     * approve-reject-approve cycle would let a child earn past the daily
     * limit. So the caps are computed from EARNED rows alone, while the
     * spendable balance is computed from every row.
     */
    public function earnedOn(Child $child, Carbon $date): int
    {
        return (int) LedgerEntry::where('child_id', $child->id)
            ->where('entry_type', LedgerEntry::EARNED)
            ->whereDate('for_date', $date->toDateString())
            ->sum('minutes');
    }

    public function earnedInWeekOf(Child $child, Carbon $date): int
    {
        $start = $date->copy()->startOfWeek(self::WEEK_STARTS_ON);
        $end = $start->copy()->addDays(6);

        return (int) LedgerEntry::where('child_id', $child->id)
            ->where('entry_type', LedgerEntry::EARNED)
            ->whereBetween('for_date', [$start->toDateString(), $end->toDateString()])
            ->sum('minutes');
    }

    private function entryFor(Submission $submission, string $type): ?LedgerEntry
    {
        return LedgerEntry::where('submission_id', $submission->id)
            ->where('entry_type', $type)
            ->first();
    }
}
