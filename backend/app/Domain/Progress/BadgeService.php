<?php

namespace App\Domain\Progress;

use App\Models\Child;
use Illuminate\Support\Carbon;
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

    /**
     * What each badge measures and how much of it earns the badge, in the
     * order the app shows them. The only place these numbers live: the app
     * receives each badge's target with the child's progress towards it.
     */
    public const GOALS = [
        self::FIRST_QUEST => ['measure' => 'quests', 'target' => 1],
        self::STREAK_7 => ['measure' => 'streak', 'target' => 7],
        self::QUESTS_25 => ['measure' => 'quests', 'target' => 25],
    ];

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

        foreach (self::GOALS as $key => $goal) {
            if (self::measured($goal, $approvedQuests, $longestStreak) >= $goal['target']) {
                $badges[] = $key;
            }
        }

        return $badges;
    }

    /**
     * Every badge in the set, earned or not, with how far the child is
     * towards it, for the Quest Log.
     *
     * @return list<array{key: string, earned_at: ?string, progress: int, target: int}>
     */
    public function statusFor(Child $child, int $approvedQuests, int $longestStreak): array
    {
        $earned = $child->badges()->pluck('earned_at', 'badge_key');

        $status = [];

        foreach (self::GOALS as $key => $goal) {
            $earnedAt = $earned[$key] ?? null;

            $status[] = [
                'key' => $key,
                'earned_at' => $earnedAt === null ? null : Carbon::parse($earnedAt)->toIso8601String(),
                // Capped at the target, so a finished bar never overflows.
                'progress' => min(self::measured($goal, $approvedQuests, $longestStreak), $goal['target']),
                'target' => $goal['target'],
            ];
        }

        return $status;
    }

    /**
     * @param  array{measure: string, target: int}  $goal
     */
    private static function measured(array $goal, int $approvedQuests, int $longestStreak): int
    {
        return $goal['measure'] === 'streak' ? $longestStreak : $approvedQuests;
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
