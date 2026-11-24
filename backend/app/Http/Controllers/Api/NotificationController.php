<?php

namespace App\Http\Controllers\Api;

use App\Domain\Model\ModelConfig;
use App\Domain\Progress\ProgressService;
use App\Domain\Verification\Routing;
use App\Http\Controllers\Controller;
use App\Models\AlarmEvent;
use App\Models\AppLockPhone;
use App\Models\Submission;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The parent's notification feed: one entry for every photo their children
 * send, newest first.
 *
 * A read over submissions rather than a table of its own, so each submission
 * is exactly one notification by construction and nothing can drift out of
 * step.
 *
 * A quest session's priority comes from its evidence (BE-5):
 *
 * - manual_check: a chore no model checks (a custom chore, or the model sat
 *   the session out), so there are no model figures to weigh;
 * - check_carefully: the evidence is weak, its class probability, seconds
 *   of matching movement or scene change under the bands in the model
 *   config;
 * - looks_genuine: otherwise.
 *
 * A single-photo submission from before sessions keeps the priority it had,
 * the photo checker's stored routing: review, approved or sent_back.
 *
 * Whether it still waits for a grown-up is its status, sent alongside. Alarm
 * events (an alarm a grown-up stopped, one that timed out, a camera that was
 * missing) come in their own list, and so do yesterday's missed quests
 * (LS-12), which are never unread: they are a note, not news.
 *
 * App Lock (AL-4, rule 10) has its own list too: each phone where it is not
 * working now, because a permission is missing or the phone has gone
 * silent. It stays in the list for as long as that lasts, and counts as
 * unread when it started after the list was last opened.
 */
class NotificationController extends Controller
{
    public function index(Request $request, ProgressService $progress): JsonResponse
    {
        $parent = $request->user();
        $childIds = $parent->children()->pluck('id');
        $seenAt = $parent->notifications_seen_at;

        $submissions = Submission::whereIn('child_id', $childIds)
            ->with(['assignment.template', 'child'])
            ->latest('id')
            ->limit(100)
            ->get();

        $alarms = AlarmEvent::whereIn('child_id', $childIds)
            ->with(['child', 'assignment.template'])
            ->latest('id')
            ->limit(50)
            ->get();

        $now = now();
        $appLock = AppLockPhone::where('user_id', $parent->id)
            ->orderBy('name')
            ->get()
            ->map(fn (AppLockPhone $phone) => [$phone, $phone->health($now)])
            ->filter(fn (array $pair) => $pair[1]['since'] !== null)
            ->map(fn (array $pair) => [
                'device_key' => $pair[0]->device_key,
                'name' => $pair[0]->name,
                'state' => $pair[1]['state'],
                'missing' => $pair[1]['missing'],
                'since' => $pair[1]['since']->toIso8601String(),
                'unread' => $seenAt === null || $pair[1]['since']->greaterThan($seenAt),
            ])
            ->values();

        $unread = Submission::whereIn('child_id', $childIds)
            ->when($seenAt, fn ($query) => $query->where('created_at', '>', $seenAt))
            ->count()
            + AlarmEvent::whereIn('child_id', $childIds)
                ->when($seenAt, fn ($query) => $query->where('created_at', '>', $seenAt))
                ->count()
            + $appLock->where('unread', true)->count();

        return response()->json([
            'unread_count' => $unread,
            'notifications' => $submissions->map(fn (Submission $s) => SubmissionController::payloadFor($s) + [
                'child_name' => $s->child->name,
                'child_avatar' => $s->child->avatar,
                'priority' => $this->priorityOf($s),
                'unread' => $seenAt === null || $s->created_at->greaterThan($seenAt),
            ])->all(),
            'alarms' => $alarms->map(fn (AlarmEvent $e) => [
                'id' => $e->id,
                'kind' => $e->kind,
                'child_id' => $e->child_id,
                'child_name' => $e->child->name,
                'child_avatar' => $e->child->avatar,
                'chore' => $e->assignment?->template?->name,
                'at' => $e->created_at->toIso8601String(),
                'unread' => $seenAt === null || $e->created_at->greaterThan($seenAt),
            ])->all(),
            'missed' => $this->missedYesterday($parent, $progress),
            'app_lock' => $appLock->all(),
        ]);
    }

    /**
     * Each child's quests missed yesterday, in the household's own day
     * (LS-12): said gently the next day, and never counted against anyone.
     *
     * @return list<array<string, mixed>>
     */
    private function missedYesterday(User $parent, ProgressService $progress): array
    {
        $out = [];
        foreach ($parent->children()->orderBy('id')->get() as $child) {
            $yesterday = $child->localNow()->subDay()->toDateString();
            foreach ($progress->missedOn($child, $yesterday) as $missed) {
                $out[] = [
                    'child_id' => $child->id,
                    'child_name' => $child->name,
                    'child_avatar' => $child->avatar,
                    'assignment_id' => $missed['assignment_id'],
                    'chore' => $missed['chore'],
                    'for_date' => $yesterday,
                ];
            }
        }

        return $out;
    }

    /**
     * The parent opened the list: everything up to now has been seen.
     */
    public function seen(Request $request): JsonResponse
    {
        $parent = $request->user();
        $parent->forceFill(['notifications_seen_at' => now()])->save();

        return response()->json(['unread_count' => 0]);
    }

    private function priorityOf(Submission $s): string
    {
        if (! $s->isSession()) {
            return match ($s->routing) {
                Routing::AUTO_APPROVED => 'approved',
                Routing::AUTO_REJECTED => 'sent_back',
                default => 'review',
            };
        }

        if ($s->verification_mode === Submission::MODE_MANUAL) {
            return 'manual_check';
        }

        return self::weak($s->model_confidence, $s->active_seconds, $s->evidence['scene_change'] ?? null)
            ? 'check_carefully'
            : 'looks_genuine';
    }

    /**
     * Whether a motion-checked session's evidence is weak: any figure under
     * its band in the model config. A scene change the phone could not
     * measure is not held against it.
     */
    public static function weak(?float $probability, ?int $activeSeconds, ?float $sceneChange): bool
    {
        $bands = ModelConfig::evidenceBands();

        return ($probability ?? 0.0) < $bands['probability']
            || ($activeSeconds ?? 0) < $bands['active_seconds']
            || ($sceneChange !== null && $sceneChange < $bands['scene_change']);
    }
}
