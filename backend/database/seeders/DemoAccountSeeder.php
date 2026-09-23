<?php

namespace Database\Seeders;

use App\Domain\Allocation\LedgerService;
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
 */
class DemoAccountSeeder extends Seeder
{
    public const PARENT_EMAIL = 'demo.parent@chorequest.test';

    public const PARENT_PASSWORD = 'demo-parent-2026';

    public const CHILD_NAME = 'Demo Hero';

    public const CHILD_PIN = '2468';

    /** Consecutive days of quests, ending yesterday. Three weeks always hold a whole Monday-to-Sunday week and a weekend. */
    private const DAYS = 21;

    /** One quest per place and difficulty, from the thesis chores (TH1). */
    private const QUESTS = [
        ['Clear the table', 'kitchen'],
        ['Make the bed', 'bedroom'],
        ['Read 10 minutes', 'study'],
        ['Water the plants', 'outdoor'],
        ['Put away the groceries', 'kitchen'],
        ['Sort laundry', 'bedroom'],
        ['Sweep the floor', 'outdoor'],
        ['Wash the dishes', 'kitchen'],
        ['Take out the rubbish', 'outdoor'],
    ];

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
        $photo = $this->placeholderPhoto();
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
                $written += $this->approvedQuest($child, $parent, $assignment, $day, $i, $photo, $ledger) ? 1 : 0;
            }
        }

        $awarded = $badges->awardFor($child);

        $this->command?->info(sprintf(
            'Demo household ready: %s / %s, child "%s" PIN %s, household code %s. '
                .'%d quests written this run over %d days (%d a day); badges newly awarded: %s.',
            self::PARENT_EMAIL, self::PARENT_PASSWORD, self::CHILD_NAME, self::CHILD_PIN, $parent->household_code,
            $written, self::DAYS, $perDay, $awarded === [] ? 'none' : implode(', ', $awarded),
        ));
    }

    /**
     * @return list<Assignment>
     */
    private function assignments(Child $child): array
    {
        $assignments = [];

        foreach (self::QUESTS as [$name, $location]) {
            $template = ChoreTemplate::where('name', $name)->first();

            if (! $template) {
                continue;
            }

            $assignments[] = $child->assignments()->firstOrCreate(
                ['chore_template_id' => $template->id],
                [
                    'points' => $template->default_points,
                    'recurrence' => 'daily',
                    'location' => $location,
                ],
            )->load('template');
        }

        return $assignments;
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

    private function approvedQuest(Child $child, User $parent, Assignment $assignment, Carbon $day, int $index, string $photo, LedgerService $ledger): bool
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

        $checked = $assignment->template->isModelVerifiable();

        $submission = $child->submissions()->create([
            'assignment_id' => $assignment->id,
            'photo_path' => $photo,
            'model_label' => $checked ? 'done' : null,
            'model_confidence' => $checked ? 0.93 : null,
            'model_version' => $checked ? 'demo' : null,
            'routing' => $checked ? Routing::AUTO_APPROVED : Routing::PENDING_REVIEW,
            'parent_decision' => $checked ? null : Decision::APPROVED,
            'parent_decided_at' => $checked ? null : $sentAt->copy()->addHour()->utc(),
            'parent_user_id' => $checked ? null : $parent->id,
            'status' => Decision::APPROVED,
            'for_date' => $day->toDateString(),
            'client_token' => $token,
        ]);
        $submission->forceFill(['created_at' => $sentAt->copy()->utc(), 'updated_at' => $sentAt->copy()->utc()])->save();

        $submission->setRelation('assignment', $assignment);
        $ledger->credit($submission);

        return true;
    }

    /** A fixed token per seeded quest, so running again finds it instead of adding a twin. */
    private function clientToken(int $childId, string $date, int $index): string
    {
        $hash = md5("chorequest-demo:{$childId}:{$date}:{$index}");

        return sprintf('%s-%s-4%s-a%s-%s', substr($hash, 0, 8), substr($hash, 8, 4), substr($hash, 13, 3), substr($hash, 17, 3), substr($hash, 20, 12));
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

    private function placeholderPng(): string
    {
        if (function_exists('imagecreatetruecolor')) {
            $image = imagecreatetruecolor(320, 240);
            imagefill($image, 0, 0, imagecolorallocate($image, 0x1C, 0x64, 0x49));
            imagestring($image, 5, 110, 110, 'Demo photo', imagecolorallocate($image, 255, 255, 255));
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
