<?php

namespace App\Domain\Progress;

use App\Domain\Verification\Decision;
use App\Models\Child;

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
}
