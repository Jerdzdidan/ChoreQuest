<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Assignment;
use App\Models\Child;
use App\Models\ChoreTemplate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
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
        ]);

        $child = $request->user()->children()->find($data['child_id']);
        abort_unless($child, 404);

        $template = ChoreTemplate::findOrFail($data['chore_template_id']);

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

        $recurrence = $data['recurrence'] ?? 'daily';

        if ($recurrence === 'once' && empty($data['scheduled_date'])) {
            throw ValidationException::withMessages([
                'scheduled_date' => ['A one-off chore needs the date it is due.'],
            ]);
        }

        $assignment = $child->assignments()->create([
            'chore_template_id' => $template->id,
            // Points are copied from the template, then owned by the parent.
            'points' => $data['points'] ?? $template->default_points,
            'due_time' => $data['due_time'] ?? null,
            'recurrence' => $recurrence,
            'scheduled_date' => $recurrence === 'once' ? $data['scheduled_date'] : null,
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
        ]);

        $assignment->update($data);

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

        $assignments = $child->assignments()
            ->dueOn(now())
            ->with('template')
            ->orderByRaw('due_time IS NULL, due_time')
            ->get();

        return response()->json([
            'date' => now()->toDateString(),
            'chores' => $assignments->map(fn (Assignment $a) => $this->payload($a))->all(),
        ]);
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
        return [
            'id' => $a->id,
            'child_id' => $a->child_id,
            'points' => $a->points,
            'due_time' => $a->due_time,
            'recurrence' => $a->recurrence,
            'scheduled_date' => $a->scheduled_date?->toDateString(),
            'is_active' => $a->is_active,
            'chore' => ChoreTemplateController::payloadFor($a->template),
        ];
    }
}
