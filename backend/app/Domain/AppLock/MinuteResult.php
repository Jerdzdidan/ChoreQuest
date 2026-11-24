<?php

namespace App\Domain\AppLock;

use App\Models\AppUnlock;

/**
 * What came of asking for one minute of an Earned time app (AL-2).
 */
final class MinuteResult
{
    /** A -1 row was written; the app may stay open for one minute. */
    public const SPENT = 'spent';

    /** Nothing written: the balance was below one minute. */
    public const NO_TIME = 'no_time';

    /** Nothing written: on this phone the app is Open or Grown-ups only. */
    public const NOT_EARNED_TIME = 'not_earned_time';

    public function __construct(
        public readonly string $outcome,
        /** The child's balance after this request. */
        public readonly int $balanceMinutes,
        /** The app's setting on this phone. */
        public readonly string $setting,
        /** Set when this minute opened the app from the lock screen. */
        public readonly ?AppUnlock $unlock = null,
    ) {}
}
