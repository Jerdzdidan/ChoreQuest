<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AlarmEvent;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * What happens to a quest alarm that the parent must hear about.
 */
class AlarmController extends Controller
{
    /**
     * POST /alarm/override (BE-10): the grown-up stop on the ring screen
     * (DV-7b). Reached with the child's token, since the phone is the
     * child's, and the household owner's account password, checked here;
     * the route is rate-limited. A wrong password never stops the alarm.
     * Every stop is recorded and reaches the parent as a notification, so it
     * cannot be used quietly.
     */
    public function override(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'password' => ['required', 'string', 'max:200'],
            'assignment_id' => ['nullable', 'integer'],
        ]);

        $owner = $child->parent;
        if (! $owner || ! Hash::check($data['password'], $owner->password)) {
            throw ValidationException::withMessages([
                'password' => ["That isn't the grown-up's password."],
            ]);
        }

        $event = AlarmEvent::create([
            'child_id' => $child->id,
            'assignment_id' => $this->ownAssignment($child, $data['assignment_id'] ?? null),
            'kind' => AlarmEvent::OVERRIDE,
        ]);

        return response()->json(['stopped' => true, 'event_id' => $event->id], 201);
    }

    /**
     * POST /my/alarm-events (child): an alarm that rang its longest and
     * stopped by itself (DV-7a), or a third-party camera that was not there
     * when it rang (DV-12). Neither stops anything; both tell the parent.
     */
    public function report(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'kind' => ['required', 'string', Rule::in(AlarmEvent::REPORTABLE)],
            'assignment_id' => ['nullable', 'integer'],
        ]);

        $event = AlarmEvent::create([
            'child_id' => $child->id,
            'assignment_id' => $this->ownAssignment($child, $data['assignment_id'] ?? null),
            'kind' => $data['kind'],
        ]);

        return response()->json(['event_id' => $event->id], 201);
    }

    /** The assignment id when it is this child's, otherwise none. */
    private function ownAssignment(Child $child, ?int $assignmentId): ?int
    {
        if ($assignmentId === null) {
            return null;
        }

        return $child->assignments()->whereKey($assignmentId)->exists() ? $assignmentId : null;
    }
}
