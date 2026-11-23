<?php

namespace Database\Seeders;

use App\Domain\Allocation\LedgerService;
use App\Domain\Chores\Catalogue;
use App\Domain\Progress\BadgeService;
use App\Domain\Progress\Difficulty;
use App\Domain\Verification\Decision;
use App\Domain\Verification\Routing;
use App\Models\Assignment;
use App\Models\Child;
use App\Models\ChoreTemplate;
use App\Models\Submission;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;

/**
 * A demo household for testing what a child sees after weeks of quests: one
 * parent, one child, and a long run of approved quests, so every badge, story
 * chapter and cosmetic can be looked at without doing real chores first.
 *
 * Local and testing environments only. Safe to run again: the accounts are
 * found by email and name, and every seeded quest carries a fixed client
 * token, so a second run adds nothing.
 *
 * How much history it writes is worked out from the rules themselves rather
 * than fixed, so the account stays past every threshold as rewards are added:
 * the badge targets come from BadgeService::GOALS, and the highest cosmetic
 * unlock level and the XP per level are read from the app's own registries
 * (mobile/lib/shared).
 *
 * Team Player, and the story chapter that follows it, need a real family
 * quest (F1-F3), so they stay locked here.
 *
 * Phase 4 (CH-6): the quests are the dataset catalogue's, found by manifest
 * key; one has a Monday, Wednesday and Friday alarm and one a daily one;
 * the parent has a custom chore, Feed the cat. Every quest written from now
 * on is a quest session, Before and After stills and an evidence summary,
 * approved by the parent, since nothing is approved automatically any more.
 * Three more sessions wait for the parent today, one of each priority:
 * Looks genuine, Check carefully and Manual check. Rows written by earlier
 * runs keep their client tokens and stay as they were.
 */
class DemoAccountSeeder extends Seeder
{
    public const PARENT_EMAIL = 'demo.parent@chorequest.test';

    public const PARENT_PASSWORD = 'demo-parent-2026';

    public const CHILD_NAME = 'Demo Hero';

    public const CHILD_PIN = '2468';

    /** Consecutive days of quests, ending yesterday. Three weeks always hold a whole Monday-to-Sunday week and a weekend. */
    private const DAYS = 21;

    /** One quest per place and difficulty, by manifest key (CH-2). */
    private const QUESTS = [
        ['clear_and_wipe_the_table', 'kitchen'],
        ['make_the_bed', 'bedroom'],
        ['read_a_book', 'study'],
        ['water_the_plants', 'outdoor'],
        ['put_away_the_groceries', 'kitchen'],
        ['sort_the_laundry', 'bedroom'],
        ['sweep_the_floor', 'outdoor'],
        ['wash_the_dishes', 'kitchen'],
        ['empty_the_bin', 'outdoor'],
    ];

    /** Alarms set on two quests, so the schedule lines and the Board's next alarm have something to show (PS-9). */
    private const SCHEDULES = [
        'sweep_the_floor' => ['days_of_week' => [1, 3, 5], 'due_time' => '16:30', 'ringtone_key' => 'steel_drums'],
        'make_the_bed' => ['days_of_week' => null, 'due_time' => '07:00', 'ringtone_key' => 'classic'],
    ];

    public const CUSTOM_CHORE = 'Feed the cat';

    public function run(LedgerService $ledger, BadgeService $badges): void
    {
        if (! app()->environment(['local', 'testing'])) {
            $this->command?->warn('DemoAccountSeeder runs only in local and testing environments.');

            return;
        }

        if (ChoreTemplate::count() === 0) {
            $this->call(ChoreTemplateSeeder::class);
        }

        $parent = User::firstOrCreate(
            ['email' => self::PARENT_EMAIL],
            [
                'name' => 'Demo Parent',
                'password' => self::PARENT_PASSWORD,
                'household_code' => User::generateHouseholdCode(),
                'avatar' => 'owl',
                'timezone' => User::DEFAULT_TIMEZONE,
            ],
        );

        /** @var Child $child */
        $child = $parent->children()->firstOrCreate(
            ['name' => self::CHILD_NAME],
            [
                'avatar' => 'lion',
                'birthdate' => now()->subYears(8)->subMonths(3)->toDateString(),
                'pin_hash' => self::CHILD_PIN,
            ],
        );

        // Room to earn: the demo is about rewards, not about the limits.
        $child->rule()->update(['daily_cap_minutes' => 600, 'weekly_cap_minutes' => 3000]);

        $assignments = $this->assignments($child);
        $custom = $this->customChore($parent, $child);
        $photo = $this->placeholderPhoto();
        $stills = [$this->still('before', 0x8A, 0x6D, 0x3B), $this->still('after', 0x1C, 0x64, 0x49)];
        $perDay = $this->questsPerDay($assignments);

        $today = $child->localNow()->startOfDay();
        $written = 0;

        // The chores were given before the history begins, so each day of it
        // counts them as due and the completion rate (ACT1) reads sensibly.
        // Only ever moved earlier, so running this again changes nothing.
        $given = $today->copy()->subDays(self::DAYS + 1)->utc();
        foreach ($assignments as $assignment) {
            if ($assignment->created_at->greaterThan($given)) {
                $assignment->forceFill(['created_at' => $given])->saveQuietly();
            }
        }

        for ($d = self::DAYS; $d >= 1; $d--) {
            $day = $today->copy()->subDays($d);

            for ($i = 0; $i < $perDay; $i++) {
                $assignment = $assignments[($d + $i) % count($assignments)];
                $written += $this->approvedQuest($child, $parent, $assignment, $day, $i, $stills, $ledger) ? 1 : 0;
            }
        }

        $waiting = $this->waitingSessions($child, $assignments, $custom, $today, $stills);

        $awarded = $badges->awardFor($child);

        $this->command?->info(sprintf(
            'Demo household ready: %s / %s, child "%s" PIN %s, household code %s. '
                .'%d quests written this run over %d days (%d a day), %d sessions waiting today; badges newly awarded: %s.',
            self::PARENT_EMAIL, self::PARENT_PASSWORD, self::CHILD_NAME, self::CHILD_PIN, $parent->household_code,
            $written, self::DAYS, $perDay, $waiting, $awarded === [] ? 'none' : implode(', ', $awarded),
        ));
        unset($photo);
    }

    /**
     * @return list<Assignment>
     */
    private function assignments(Child $child): array
    {
        $assignments = [];

        foreach (self::QUESTS as [$key, $location]) {
            $template = ChoreTemplate::where('key', $key)->first();

            if (! $template) {
                continue;
            }

            $assignment = $child->assignments()->firstOrCreate(
                ['chore_template_id' => $template->id],
                [
                    'points' => $template->default_points,
                    'recurrence' => 'daily',
                    'location' => $location,
                ],
            );

            // Set once: an alarm already there is the parent's to keep.
            if (isset(self::SCHEDULES[$key]) && $assignment->due_time === null) {
                $assignment->update(self::SCHEDULES[$key]);
            }

            $assignments[] = $assignment->load('template');
        }

        return $assignments;
    }

    /** The parent's own chore, assigned to the child: checked only by the parent (PS-2). */
    private function customChore(User $parent, Child $child): Assignment
    {
        $template = ChoreTemplate::firstOrCreate(
            ['is_custom' => true, 'owner_user_id' => $parent->id, 'name' => self::CUSTOM_CHORE],
            [
                'description' => 'One scoop of food and fresh water',
                'icon' => 'pet',
                'category' => Catalogue::CUSTOM,
                'location' => 'other',
                'min_age' => 4,
                'max_age' => 10,
                'default_points' => 3,
                'difficulty' => Difficulty::Easy,
                'verification_mode' => ChoreTemplate::MODE_MANUAL,
            ],
        );

        return $child->assignments()->firstOrCreate(
            ['chore_template_id' => $template->id],
            ['points' => 3, 'recurrence' => 'daily', 'location' => 'other'],
        )->load('template');
    }

    /**
     * Three sessions waiting for the parent today, one of each priority
     * (BE-5): strong evidence (Looks genuine), weak evidence (Check
     * carefully), and the custom chore (Manual check). Fixed tokens per day,
     * so running again the same day adds nothing.
     *
     * @param  list<Assignment>  $assignments
     * @param  array{0: string, 1: string}  $stills
     */
    private function waitingSessions(Child $child, array $assignments, Assignment $custom, Carbon $today, array $stills): int
    {
        $byKey = collect($assignments)->keyBy(fn (Assignment $a) => $a->template->key);
        $waiting = array_filter([
            [$byKey->get('sweep_the_floor'), 'strong'],
            [$byKey->get('wash_the_dishes'), 'weak'],
            [$custom, 'manual'],
        ], fn ($pair) => $pair[0] !== null);

        $written = 0;
        foreach (array_values($waiting) as $i => [$assignment, $kind]) {
            $token = $this->clientToken($child->id, $today->toDateString().':waiting', $i);
            if (Submission::where('client_token', $token)->exists()) {
                continue;
            }
            $sentAt = $today->copy()->setTime(9, 15)->addMinutes(25 * $i);
            $this->session($child, $assignment, $today, $sentAt, $token, $stills, $kind, approvedBy: null);
            $written++;
        }

        return $written;
    }

    /**
     * Enough quests a day that the whole run clears every badge's quest target,
     * every place's target, the busiest-day target, and the XP for the highest
     * cosmetic level plus one more: worked out, not fixed.
     *
     * @param  list<Assignment>  $assignments
     */
    private function questsPerDay(array $assignments): int
    {
        $goals = collect(BadgeService::GOALS);
        $questsNeeded = (int) $goals->where('measure', 'quests')->max('target');
        $perPlaceNeeded = (int) $goals->filter(fn ($goal) => str_starts_with($goal['measure'], 'location:'))->max('target');
        $bestDayNeeded = (int) $goals->where('measure', 'best_day')->max('target');
        $xpNeeded = $this->xpForLevel($this->highestUnlockLevel() + 1);

        $averageXp = collect($assignments)->avg(fn (Assignment $a) => $a->template->difficulty->xp()) ?: Difficulty::Easy->xp();
        $places = max(1, collect($assignments)->pluck('location')->unique()->count());

        $perDay = max(
            $bestDayNeeded,
            (int) ceil($questsNeeded / self::DAYS),
            (int) ceil($perPlaceNeeded * $places / self::DAYS),
            (int) ceil($xpNeeded / $averageXp / self::DAYS),
        );

        // One of each quest a day at most: the app refuses a second approval of
        // the same quest on the same day.
        return min($perDay + 1, count($assignments));
    }

    /**
     * @param  array{0: string, 1: string}  $stills
     */
    private function approvedQuest(Child $child, User $parent, Assignment $assignment, Carbon $day, int $index, array $stills, LedgerService $ledger): bool
    {
        $token = $this->clientToken($child->id, $day->toDateString(), $index);

        if (Submission::where('client_token', $token)->exists()) {
            return false;
        }

        // The first quest of each day before 9am, household time (Early Bird);
        // the rest through the afternoon.
        $sentAt = $index === 0
            ? $day->copy()->setTime(7, 30)
            : $day->copy()->setTime(15, 0)->addMinutes(20 * $index);

        $submission = $this->session($child, $assignment, $day, $sentAt, $token, $stills, 'strong', approvedBy: $parent);
        $ledger->credit($submission);

        return true;
    }

    /**
     * One quest session as the phone would send it (BE-2): Before and After
     * stills and an evidence summary, pending and routed pending_review, and
     * approved by [approvedBy] when given. [kind] picks the evidence: strong,
     * weak (a low class probability and a short spell of movement), or manual
     * (no model figures), which a chore no model checks always is.
     *
     * @param  array{0: string, 1: string}  $stills
     */
    private function session(Child $child, Assignment $assignment, Carbon $day, Carbon $sentAt, string $token, array $stills, string $kind, ?User $approvedBy): Submission
    {
        $template = $assignment->template;
        $motion = $template->isMotionChecked() && $kind !== 'manual';
        $weak = $kind === 'weak';
        $active = $motion ? ($weak ? 8 : max(30, (int) $template->min_active_seconds + 15)) : null;
        $session = $motion ? $active + 40 : 75;
        $started = $sentAt->copy()->subSeconds($session);
        $probability = $weak ? 0.44 : 0.86;

        $evidence = array_filter([
            'mode' => $motion ? 'lstm' : 'manual',
            'model_version' => $motion ? 'demo' : null,
            'chore_key' => $template->key,
            'session_seconds' => $session,
            'active_seconds' => $active,
            'mean_probability' => $motion ? $probability : null,
            'max_probability' => $motion ? min(1.0, $probability + 0.1) : null,
            'matched_share' => $motion ? round($active / $session, 2) : null,
            'timeline' => $motion
                ? array_map(fn ($s) => [$s, $s < 10 ? 0.15 : $probability], range(0, $session, 5))
                : null,
            'scene_change' => $weak ? 0.04 : 0.32,
            'camera' => 'phone_back',
            'camera_flipped' => false,
            'mean_model_ms' => $motion ? 46 : null,
            'phone_model' => 'Demo phone',
            'started_at' => $started->toIso8601String(),
            'finished_at' => $sentAt->toIso8601String(),
        ], fn ($value) => $value !== null);

        $submission = $child->submissions()->create([
            'assignment_id' => $assignment->id,
            'before_photo_path' => $stills[0],
            'photo_path' => $stills[1],
            'model_label' => $motion ? $template->key : null,
            'model_confidence' => $motion ? $probability : null,
            'model_version' => $motion ? 'demo' : null,
            'inference_ms' => $motion ? 46 : null,
            'evidence' => $evidence,
            'session_started_at' => $started->copy()->utc(),
            'session_done_at' => $sentAt->copy()->utc(),
            'active_seconds' => $active,
            'verification_mode' => $motion ? Submission::MODE_LSTM : Submission::MODE_MANUAL,
            'camera_source' => 'phone',
            'routing' => Routing::PENDING_REVIEW,
            'parent_decision' => $approvedBy ? Decision::APPROVED : null,
            'parent_decided_at' => $approvedBy ? $sentAt->copy()->addHour()->utc() : null,
            'parent_user_id' => $approvedBy?->id,
            'status' => $approvedBy ? Decision::APPROVED : Decision::PENDING,
            'for_date' => $day->toDateString(),
            'client_token' => $token,
        ]);
        $submission->forceFill(['created_at' => $sentAt->copy()->utc(), 'updated_at' => $sentAt->copy()->utc()])->save();
        $submission->setRelation('assignment', $assignment);

        return $submission;
    }

    /** A fixed token per seeded quest, so running again finds it instead of adding a twin. */
    private function clientToken(int $childId, string $date, int $index): string
    {
        $hash = md5("chorequest-demo:{$childId}:{$date}:{$index}");

        return sprintf('%s-%s-4%s-a%s-%s', substr($hash, 0, 8), substr($hash, 8, 4), substr($hash, 13, 3), substr($hash, 17, 3), substr($hash, 20, 12));
    }

    /** A labelled Before or After still for the demo sessions, kept off the public disk like real ones. */
    private function still(string $which, int $red, int $green, int $blue): string
    {
        $path = "submissions/demo/{$which}.png";

        if (! Storage::disk('local')->exists($path)) {
            Storage::disk('local')->put($path, $this->placeholderPng(ucfirst($which), [$red, $green, $blue]));
        }

        return $path;
    }

    /** One small picture stands in for every demo photo, kept off the public disk like real ones. */
    private function placeholderPhoto(): string
    {
        $path = 'submissions/demo/placeholder.png';

        if (! Storage::disk('local')->exists($path)) {
            Storage::disk('local')->put($path, $this->placeholderPng());
        }

        return $path;
    }

    /**
     * @param  array{0: int, 1: int, 2: int}  $colour
     */
    private function placeholderPng(string $label = 'Demo photo', array $colour = [0x1C, 0x64, 0x49]): string
    {
        if (function_exists('imagecreatetruecolor')) {
            $image = imagecreatetruecolor(320, 240);
            imagefill($image, 0, 0, imagecolorallocate($image, ...$colour));
            imagestring($image, 5, 160 - 4 * strlen($label), 110, $label, imagecolorallocate($image, 255, 255, 255));
            ob_start();
            imagepng($image);

            return (string) ob_get_clean();
        }

        return base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==');
    }

    /**
     * The highest level any cosmetic or animal waits for, read from the app's
     * registries so new entries raise it by themselves. 10 if they cannot be
     * read, comfortably past today's 6.
     */
    private function highestUnlockLevel(): int
    {
        $levels = [];

        foreach (['outfits', 'headwear', 'pets', 'room_items', 'avatars'] as $file) {
            $path = base_path("../mobile/lib/shared/{$file}.dart");
            if (is_file($path) && preg_match_all('/unlockLevel:\s*(\d+)/', (string) file_get_contents($path), $matches)) {
                $levels = array_merge($levels, array_map('intval', $matches[1]));
            }
        }

        return $levels === [] ? 10 : max($levels);
    }

    /** XP to reach $level, by the app's own rule in leveling.dart (100 a level if it cannot be read). */
    private function xpForLevel(int $level): int
    {
        $path = base_path('../mobile/lib/shared/leveling.dart');
        $perLevel = is_file($path) && preg_match('/const xpPerLevel\s*=\s*(\d+);/', (string) file_get_contents($path), $match)
            ? (int) $match[1]
            : 100;

        return ($level - 1) * $perLevel;
    }
}
