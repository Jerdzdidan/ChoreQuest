<?php

namespace App\Domain\AppLock;

use App\Domain\Allocation\LedgerService;
use App\Models\AppRule;
use App\Models\AppUnlock;
use App\Models\Child;
use App\Models\LedgerEntry;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Spending earned minutes on a locked app, one minute at a time (AL-2,
 * decision 5, rule 9).
 *
 * Only the server spends: each minute is a -1 'consumed' row in the
 * ledger, written here or not at all, and the phone keeps the app open
 * for the one minute it was given. At zero nothing is written and the app
 * stays locked; the balance never goes below zero by spending.
 */
class ScreenTime
{
    /** Each minute's ledger note; the app's package follows. */
    public const NOTE_PREFIX = 'App Lock: ';

    public function __construct(
        private readonly LedgerService $ledger,
        private readonly RuleBook $rules,
    ) {}

    /**
     * One minute of $package on the phone $deviceKey.
     *
     * $opening is true for the minute that opens the app from the lock
     * screen, which also records the unlock (rule 10), and false for each
     * minute after it.
     *
     * $today is the household's date now; the minute counts against it.
     */
    public function spendMinute(Child $child, string $deviceKey, string $package, bool $opening, Carbon $today): MinuteResult
    {
        return DB::transaction(function () use ($child, $deviceKey, $package, $opening, $today) {
            // One at a time per child, so two phones asking at once cannot
            // both spend the last minute.
            $locked = Child::whereKey($child->id)->lockForUpdate()->firstOrFail();

            $setting = $this->rules->settingFor($locked->user_id, $deviceKey, $package);
            $balance = $this->ledger->balance($locked);

            if ($setting !== AppRule::EARNED_TIME) {
                return new MinuteResult(MinuteResult::NOT_EARNED_TIME, $balance, $setting);
            }

            if ($balance < 1) {
                return new MinuteResult(MinuteResult::NO_TIME, $balance, $setting);
            }

            LedgerEntry::create([
                'child_id' => $locked->id,
                'entry_type' => LedgerEntry::CONSUMED,
                'minutes' => -1,
                'for_date' => $today->toDateString(),
                'note' => self::NOTE_PREFIX.$package,
            ]);

            $unlock = $opening
                ? AppUnlock::create([
                    'user_id' => $locked->user_id,
                    'device_key' => $deviceKey,
                    'package' => $package,
                    'method' => AppUnlock::CHILD_MINUTES,
                    'child_id' => $locked->id,
                ])
                : null;

            return new MinuteResult(MinuteResult::SPENT, $balance - 1, $setting, $unlock);
        });
    }
}
