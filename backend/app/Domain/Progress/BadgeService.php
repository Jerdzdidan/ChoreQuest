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
 * done lowers XP, which is counted afresh, but does not take back a badge,
 * which records a moment the child reached. Taking one away would turn a
 * parent's second look into a punishment.
 */
class BadgeService
{
    public const FIRST_QUEST = 'first_quest';

    public const STREAK_7 = 'streak_7';

    public const QUESTS_25 = 'quests_25';

    public const KITCHEN_HERO = 'kitchen_hero';

    public const BEDROOM_HERO = 'bedroom_hero';

    public const STUDY_STAR = 'study_star';

    public const OUTDOOR_EXPLORER = 'outdoor_explorer';

    public const EARLY_BIRD = 'early_bird';

    public const WEEKEND_WARRIOR = 'weekend_warrior';

    public const PERFECT_WEEK = 'perfect_week';

    public const HELPING_HAND = 'helping_hand';

    public const CENTURY_CLUB = 'century_club';

    public const TEAM_PLAYER = 'team_player';

    /**
     * What each badge measures and how much of it earns the badge, in the
     * order the app shows them. The only place these numbers live: the app
     * receives each badge's target with the child's progress towards it.
     *
     * Measures are read from BadgeStats, which works them out from the
     * child's approved quests in the household's own timezone.
     */
    public const GOALS = [
        self::FIRST_QUEST => ['measure' => 'quests', 'target' => 1],
        self::STREAK_7 => ['measure' => 'streak', 'target' => 7],
        self::QUESTS_25 => ['measure' => 'quests', 'target' => 25],
        self::KITCHEN_HERO => ['measure' => 'location:kitchen', 'target' => 10],
        self::BEDROOM_HERO => ['measure' => 'location:bedroom', 'target' => 10],
        self::STUDY_STAR => ['measure' => 'location:study', 'target' => 10],
        self::OUTDOOR_EXPLORER => ['measure' => 'location:outdoor', 'target' => 10],
        self::EARLY_BIRD => ['measure' => 'early_bird', 'target' => 1],
        self::WEEKEND_WARRIOR => ['measure' => 'weekend', 'target' => 1],
        self::PERFECT_WEEK => ['measure' => 'perfect_week', 'target' => 1],
        self::HELPING_HAND => ['measure' => 'best_day', 'target' => 5],
        self::CENTURY_CLUB => ['measure' => 'quests', 'target' => 100],
        self::TEAM_PLAYER => ['measure' => 'family', 'target' => 1],
    ];

    public function __construct(private readonly ProgressService $progress)
    {
    }

    /**
     * Which badges these figures have reached. Pure: the same figures always
     * give the same badges.
     *
     * @return list<string>
     */
    public static function reached(BadgeStats $stats): array
    {
        $badges = [];

        foreach (self::GOALS as $key => $goal) {
            if (self::measured($goal, $stats) >= $goal['target']) {
                $badges[] = $key;
            }
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
        $reached = self::reached($this->progress->badgeStats($child));

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

    /**
     * Every badge in the set, earned or not, with how far the child is
     * towards it, for the Quest Log.
     *
     * @return list<array{key: string, earned_at: ?string, progress: int, target: int}>
     */
    public function statusFor(Child $child, BadgeStats $stats): array
    {
        $earned = $child->badges()->pluck('earned_at', 'badge_key');

        $status = [];

        foreach (self::GOALS as $key => $goal) {
            $earnedAt = $earned[$key] ?? null;

            $status[] = [
                'key' => $key,
                'earned_at' => $earnedAt === null ? null : Carbon::parse($earnedAt)->toIso8601String(),
                // Capped at the target, so a finished bar never overflows.
                'progress' => min(self::measured($goal, $stats), $goal['target']),
                'target' => $goal['target'],
            ];
        }

        return $status;
    }

    /**
     * @param  array{measure: string, target: int}  $goal
     */
    private static function measured(array $goal, BadgeStats $stats): int
    {
        return match (true) {
            $goal['measure'] === 'quests' => $stats->quests,
            $goal['measure'] === 'streak' => $stats->longestStreak,
            $goal['measure'] === 'early_bird' => $stats->earlyBirdQuests,
            $goal['measure'] === 'weekend' => $stats->weekendPairs,
            $goal['measure'] === 'perfect_week' => $stats->perfectWeeks,
            $goal['measure'] === 'best_day' => $stats->bestDay,
            $goal['measure'] === 'family' => $stats->familyContributions,
            str_starts_with($goal['measure'], 'location:') => $stats->questsIn(substr($goal['measure'], 9)),
            default => 0,
        };
    }
}
