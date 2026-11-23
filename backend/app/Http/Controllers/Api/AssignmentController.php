<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Assignment;
use App\Models\Child;
use App\Models\ChoreTemplate;
use App\Models\DeviceCamera;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AssignmentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate(['child_id' => ['required', 'integer']]);

        $child = $request->user()->children()->find($request->integer('child_id'));
        abort_unless($child, 404);

        $assignments = $child->assignments()->with('template')->orderBy('due_time')->get();

        return response()->json([
            'assignments' => $assignments->map(fn (Assignment $a) => $this->payload($a))->all(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'child_id' => ['required', 'integer'],
            'chore_template_id' => ['required', 'integer', 'exists:chore_templates,id'],
            'points' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'due_time' => ['nullable', 'date_format:H:i'],
            'recurrence' => ['sometimes', 'in:daily,once'],
            'scheduled_date' => ['nullable', 'date'],
            'location' => ['sometimes', 'string', Rule::in(Assignment::LOCATIONS)],
            ...$this->scheduleRules(),
        ]);

        $child = $request->user()->children()->find($data['child_id']);
        abort_unless($child, 404);

        $template = ChoreTemplate::visibleTo($request->user())->find($data['chore_template_id']);

        // Another parent's custom chore is as good as absent. A retired chore
        // keeps the assignments it already has but takes no new ones.
        if (! $template || $template->isRetired()) {
            throw ValidationException::withMessages([
                'chore_template_id' => [$template
                    ? sprintf('"%s" is no longer in the catalogue.', $template->name)
                    : 'That chore is not in your catalogue.'],
            ]);
        }

        // A chore outside the child's age band is refused rather than silently
        // accepted. The age grading is a safety claim in Chapter 1, not a hint.
        if (! $template->suitsAge($child->age())) {
            throw ValidationException::withMessages([
                'chore_template_id' => [sprintf(
                    '"%s" is meant for ages %d to %d, and %s is %d.',
                    $template->name, $template->min_age, $template->max_age, $child->name, $child->age()
                )],
            ]);
        }

        $assignment = $child->assignments()->create([
            'chore_template_id' => $template->id,
            // Points are copied from the template, then owned by the parent.
            'points' => $data['points'] ?? $template->default_points,
            // Where in the home it happens, chosen by the parent. Without one,
            // the quest is grouped under "other" on the child's map.
            'location' => $data['location'] ?? 'other',
            ...$this->schedule($data, $child),
        ]);

        return response()->json(['assignment' => $this->payload($assignment->load('template'))], 201);
    }

    public function update(Request $request, Assignment $assignment): JsonResponse
    {
        $this->authoriseOwnership($request, $assignment);

        $data = $request->validate([
            'points' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'due_time' => ['nullable', 'date_format:H:i'],
            'is_active' => ['sometimes', 'boolean'],
            'location' => ['sometimes', 'string', Rule::in(Assignment::LOCATIONS)],
            'recurrence' => ['sometimes', 'in:daily,once'],
            'scheduled_date' => ['nullable', 'date'],
            ...$this->scheduleRules(),
        ]);

        // The schedule can be changed after the quest is set (PS-7): what is
        // sent replaces what was there, the rest is kept, and the whole is
        // checked as if it were new.
        $schedule = array_intersect_key($data, array_flip([
            'due_time', 'recurrence', 'scheduled_date', 'days_of_week',
            'ringtone_key', 'camera_source', 'camera_device_id', 'alarm_enabled',
        ]));
        $rest = array_diff_key($data, $schedule);

        if ($schedule !== []) {
            $rest += $this->schedule($schedule + [
                'due_time' => $assignment->due_time === null ? null : substr($assignment->due_time, 0, 5),
                'recurrence' => $assignment->recurrence,
                'scheduled_date' => $assignment->scheduled_date?->toDateString(),
                'days_of_week' => $assignment->days_of_week,
                'ringtone_key' => $assignment->ringtone_key,
                'camera_source' => $assignment->camera_source,
                'camera_device_id' => $assignment->camera_device_id,
                'alarm_enabled' => $assignment->alarm_enabled,
            ], $assignment->child, $assignment->camera_device_id);
        }

        $assignment->update($rest);

        return response()->json(['assignment' => $this->payload($assignment->fresh()->load('template'))]);
    }

    public function destroy(Request $request, Assignment $assignment): JsonResponse
    {
        $this->authoriseOwnership($request, $assignment);
        $assignment->delete();

        return response()->json(['message' => 'Assignment removed.']);
    }

    /**
     * The child-facing list. Reached with a `child` ability token, so it can
     * only ever return the caller's own chores.
     */
    public function today(Request $request): JsonResponse
    {
        $child = $request->user();
        // Today where the household lives, not on the server's UTC clock.
        $now = $child->localNow();

        $assignments = $child->assignments()
            ->dueOn($now)
            ->with('template')
            ->orderByRaw('due_time IS NULL, due_time')
            ->get();

        return response()->json([
            'date' => $now->toDateString(),
            'chores' => $assignments->map(fn (Assignment $a) => $this->payload($a))->all(),
        ]);
    }

    /**
     * The schedule fields a parent may send (PS-7).
     *
     * @return array<string, list<mixed>>
     */
    private function scheduleRules(): array
    {
        return [
            // ISO weekdays, 1 Monday to 7 Sunday. At least one when given.
            'days_of_week' => ['nullable', 'array', 'min:1', 'max:7'],
            'days_of_week.*' => ['integer', 'between:1,7', 'distinct'],
            // A key from the app's ringtone registry; its shape is all the
            // server can check.
            'ringtone_key' => ['sometimes', 'string', 'regex:/^[a-z0-9_]{1,30}$/'],
            'camera_source' => ['sometimes', 'string', Rule::in(Assignment::CAMERA_SOURCES)],
            'camera_device_id' => ['nullable', 'string', 'max:100'],
            'alarm_enabled' => ['sometimes', 'boolean'],
        ];
    }

    /**
     * The stored schedule for what was sent, with the rules that hold across
     * fields: a one-time quest needs its date, has no weekdays and always
     * uses the phone camera (the parent sees no camera control for it); a
     * daily quest has no date; a third-party camera must be named, and be
     * one the child's phone has reported (BE-8). A camera already on the
     * assignment is kept even if the phone no longer lists it, so editing
     * the alarm never fails over it; the session falls back to the phone
     * camera when it is missing (DV-12).
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function schedule(array $data, Child $child, ?string $currentCamera = null): array
    {
        $recurrence = $data['recurrence'] ?? 'daily';

        if ($recurrence === 'once' && empty($data['scheduled_date'])) {
            throw ValidationException::withMessages([
                'scheduled_date' => ['A one-off chore needs the date it is due.'],
            ]);
        }

        $camera = $recurrence === 'once'
            ? Assignment::CAMERA_PHONE
            : ($data['camera_source'] ?? Assignment::CAMERA_PHONE);

        if ($camera === Assignment::CAMERA_EXTERNAL && empty($data['camera_device_id'])) {
            throw ValidationException::withMessages([
                'camera_device_id' => ['Choose which third-party camera to use.'],
            ]);
        }

        if ($camera === Assignment::CAMERA_EXTERNAL
            && $data['camera_device_id'] !== $currentCamera
            && ! DeviceCamera::where('child_id', $child->id)->thirdParty()->where('camera_key', $data['camera_device_id'])->exists()) {
            throw ValidationException::withMessages([
                'camera_device_id' => ["That camera has not been connected to {$child->name}'s phone."],
            ]);
        }

        $days = $data['days_of_week'] ?? null;
        if ($days !== null) {
            $days = array_values(array_unique(array_map('intval', $days)));
            sort($days);
        }

        return [
            'due_time' => $data['due_time'] ?? null,
            'recurrence' => $recurrence,
            'scheduled_date' => $recurrence === 'once' ? $data['scheduled_date'] : null,
            'days_of_week' => $recurrence === 'daily' ? $days : null,
            'ringtone_key' => $data['ringtone_key'] ?? Assignment::DEFAULT_RINGTONE,
            'camera_source' => $camera,
            'camera_device_id' => $camera === Assignment::CAMERA_EXTERNAL ? $data['camera_device_id'] : null,
            'alarm_enabled' => $data['alarm_enabled'] ?? true,
        ];
    }

    private function authoriseOwnership(Request $request, Assignment $assignment): void
    {
        abort_unless(
            $assignment->child()->where('user_id', $request->user()->id)->exists(),
            404
        );
    }

    private function payload(Assignment $a): array
    {
        return self::payloadFor($a);
    }

    public static function payloadFor(Assignment $a): array
    {
        return [
            'id' => $a->id,
            'child_id' => $a->child_id,
            'points' => $a->points,
            'due_time' => $a->due_time,
            'recurrence' => $a->recurrence,
            'scheduled_date' => $a->scheduled_date?->toDateString(),
            // PS-7: null means every day.
            'days_of_week' => $a->days_of_week,
            'ringtone_key' => $a->ringtone_key,
            'camera_source' => $a->camera_source,
            'camera_device_id' => $a->camera_device_id,
            'alarm_enabled' => $a->alarm_enabled,
            'is_active' => $a->is_active,
            'location' => $a->location,
            'chore' => ChoreTemplateController::payloadFor($a->template),
        ];
    }
}
