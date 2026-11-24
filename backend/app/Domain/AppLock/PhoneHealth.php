<?php

namespace App\Domain\AppLock;

use Illuminate\Support\Carbon;

/**
 * Whether App Lock is working on a phone, from what it last reported
 * (AL-4, rule 10). Pure: the report and the time now are passed in.
 *
 * - working: it reported within SILENT_AFTER_MINUTES, with every
 *   permission App Lock needs;
 * - needs_attention: its last report says a permission is missing;
 * - silent: it has not reported for SILENT_AFTER_MINUTES. The watcher may
 *   have been stopped, ChoreQuest uninstalled, or the phone is off or
 *   offline. From here nobody can tell which, so the parent is told all
 *   of them.
 */
final class PhoneHealth
{
    /** What App Lock needs on the phone, as the watcher reports them. */
    public const CHECKS = ['usage_access', 'overlay', 'notifications', 'battery'];

    /** The watcher reports every 15 minutes; four missed reports is silence. */
    public const SILENT_AFTER_MINUTES = 60;

    public const WORKING = 'working';

    public const NEEDS_ATTENTION = 'needs_attention';

    public const SILENT = 'silent';

    /**
     * The permissions a report says are missing, in CHECKS order. A check
     * the phone did not send counts as missing.
     *
     * @param  array<string, mixed>|null  $checks
     * @return list<string>
     */
    public static function missing(?array $checks): array
    {
        return array_values(array_filter(self::CHECKS, fn (string $name) => ($checks[$name] ?? false) !== true));
    }

    /**
     * When the current stretch of missing permissions began, after a new
     * report: kept while something is still missing, started now when
     * something has just gone missing, and cleared when nothing is.
     *
     * @param  array<string, mixed>  $checks
     */
    public static function problemsSinceAfter(array $checks, ?Carbon $problemsSince, Carbon $now): ?Carbon
    {
        return self::missing($checks) === [] ? null : ($problemsSince ?? $now);
    }

    /**
     * The phone's state, and since when it has been in it: the start of
     * the stretch of missing permissions, or the moment it fell silent.
     * Null when working.
     *
     * $since is when App Lock was turned on, for a phone that has never
     * reported.
     *
     * @param  array<string, mixed>|null  $checks
     * @return array{state: string, since: ?Carbon, missing: list<string>}
     */
    public static function of(?array $checks, ?Carbon $problemsSince, ?Carbon $reportedAt, Carbon $turnedOnAt, Carbon $now): array
    {
        $heard = $reportedAt ?? $turnedOnAt;
        $silentFrom = $heard->copy()->addMinutes(self::SILENT_AFTER_MINUTES);
        // What the last report said; a phone that never reported said nothing.
        $missing = $reportedAt === null ? [] : self::missing($checks);

        if ($now->greaterThanOrEqualTo($silentFrom)) {
            return ['state' => self::SILENT, 'since' => $silentFrom, 'missing' => $missing];
        }

        if ($missing !== []) {
            return ['state' => self::NEEDS_ATTENTION, 'since' => $problemsSince ?? $reportedAt, 'missing' => $missing];
        }

        return ['state' => self::WORKING, 'since' => null, 'missing' => []];
    }
}
