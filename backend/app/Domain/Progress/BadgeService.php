<?php

namespace App\Domain\Progress;

use App\Models\Child;
use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Milestone badges, checked after every approval.
 *
 * A badge, once earned, is kept. A grown-up later changing an approval to not
 * done lowers XP, which is a count, but does not take back a badge, which
 * records a moment the child reached. Taking one away would turn a parent's
 * second look into a punishment.
 */
class BadgeService
{
    public const FIRST_QUEST = 'first_quest';

    public const STREAK_7 = 'streak_7';

    public const QUESTS_25 = 'quests_25';

    public function __construct(private readonly ProgressService $progress)
    {
    }

    /**
     * Which badges these figures have reached. Pure: the same numbers always
     * give the same badges.
     *
     * @return list<string>
     */
    public static function reached(int $approvedQuests, int $longestStreak): array
    {
        $badges = [];

        if ($approvedQuests >= 1) {
            $badges[] = self::FIRST_QUEST;
        }

        if ($longestStreak >= 7) {
            $badges[] = self::STREAK_7;
        }

        if ($approvedQuests >= 25) {
            $badges[] = self::QUESTS_25;
        }

        return $badges;
    }

    /**
     * Records every badge this child has reached and does not already hold.
     *
     * Safe to call any number of times. The unique index on (child_id,
     * badge_key) makes a repeat a no-op rather than a second row, including
     * when two approvals land at the same moment.
     *
     * @return list<string> the badges this call awarded
     */
    public function awardFor(Child $child): array
    {
        $reached = self::reached(
            $this->progress->xp($child),
            $this->progress->longestStreak($child),
        );

        $awarded = [];

        foreach ($reached as $key) {
            $inserted = DB::table('badges_earned')->insertOrIgnore([
                'child_id' => $child->id,
                'badge_key' => $key,
                'earned_at' => now(),
            ]);

            if ($inserted > 0) {
                $awarded[] = $key;
            }
        }

        return $awarded;
    }

    /**
     * For the approval paths. A badge is a bonus: if awarding fails, the
     * failure is logged and the approval, with the screen time it released,
     * stands.
     *
     * @return list<string>
     */
    public function awardAfterApproval(Child $child): array
    {
        try {
            return $this->awardFor($child);
        } catch (Throwable $e) {
            report($e);

            return [];
        }
    }
}
