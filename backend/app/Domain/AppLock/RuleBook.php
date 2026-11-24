<?php

namespace App\Domain\AppLock;

use App\Models\AppRule;
use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Which apps are locked on a phone (AL-2). Rules belong to a household and
 * one phone of it (decision 4: App Lock covers the phone it was set up on).
 * An app with no rule is Open.
 */
class RuleBook
{
    /** @return Collection<int, AppRule> */
    public function forPhone(int $householdId, string $deviceKey): Collection
    {
        return AppRule::where('user_id', $householdId)
            ->where('device_key', $deviceKey)
            ->orderBy('package')
            ->get();
    }

    /** Open, Earned time or Grown-ups only. */
    public function settingFor(int $householdId, string $deviceKey, string $package): string
    {
        return AppRule::where('user_id', $householdId)
            ->where('device_key', $deviceKey)
            ->where('package', $package)
            ->value('setting') ?? AppRule::OPEN;
    }

    /**
     * Set some of a phone's apps, all or none. Open removes an app's rule;
     * the other two are written in one statement per app, so two grown-ups
     * setting the same app at once cannot trip the unique index.
     *
     * @param  list<array{package: string, setting: string}>  $changes
     * @return Collection<int, AppRule> the phone's rules afterwards
     */
    public function apply(User $household, User $by, string $deviceKey, array $changes): Collection
    {
        DB::transaction(function () use ($household, $by, $deviceKey, $changes) {
            foreach ($changes as $change) {
                if ($change['setting'] === AppRule::OPEN) {
                    AppRule::where('user_id', $household->id)
                        ->where('device_key', $deviceKey)
                        ->where('package', $change['package'])
                        ->delete();

                    continue;
                }

                AppRule::upsert(
                    [[
                        'user_id' => $household->id,
                        'device_key' => $deviceKey,
                        'package' => $change['package'],
                        'setting' => $change['setting'],
                        'set_by' => $by->id,
                    ]],
                    ['user_id', 'device_key', 'package'],
                    ['setting', 'set_by'],
                );
            }
        });

        return $this->forPhone($household->id, $deviceKey);
    }
}
