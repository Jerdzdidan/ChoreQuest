<?php

namespace App\Http\Controllers\Api;

use App\Domain\Chores\Catalogue;
use App\Domain\Progress\Difficulty;
use App\Http\Controllers\Controller;
use App\Models\Assignment;
use App\Models\Child;
use App\Models\ChoreTemplate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class ChoreTemplateController extends Controller
{
    /**
     * The catalogue a parent browses: the categories to pick from, in order
     * with Custom chore last, and the chores still offered, which are the
     * shared catalogue plus this parent's own custom chores. Retired chores
     * are left out. Pass ?child_id= to see only what suits that child's age
     * -- which is the normal way the app calls this.
     */
    public function index(Request $request): JsonResponse
    {
        $query = ChoreTemplate::query()
            ->offered()
            ->visibleTo($request->user())
            ->orderBy('min_age')
            ->orderBy('name');

        if ($request->filled('child_id')) {
            $child = $request->user()->children()->find($request->integer('child_id'));
            abort_unless($child, 404);
            $query->forAge($child->age());
        }

        return response()->json([
            'categories' => Catalogue::categories(),
            'chores' => $query->get()->map(fn (ChoreTemplate $t) => $this->payload($t))->all(),
        ]);
    }

    /**
     * A chore the parent makes up (PS-2). It is outside the datasets by
     * definition, so it has no model and is always checked by the parent:
     * verification_mode manual, no class, no minimum time. It is for ages 4
     * to 10, belongs to the Custom chore category, and is seen only by the
     * parent who made it. Its points follow from the difficulty the parent
     * picks, which also sets its XP through the difficulty rules.
     */
    public function storeCustom(Request $request): JsonResponse
    {
        $parent = $request->user();

        $data = $request->validate([
            'name' => ['required', 'string', 'max:60'],
            'description' => ['nullable', 'string', 'max:200'],
            // A key from the app's chore icon set; its shape is all the
            // server can check.
            'icon' => ['required', 'string', 'regex:/^[a-z_]{1,40}$/'],
            'location' => ['required', 'string', Rule::in(Assignment::LOCATIONS)],
            'difficulty' => ['required', Rule::enum(Difficulty::class)],
        ]);

        $name = trim($data['name']);
        $taken = ChoreTemplate::where('is_custom', true)
            ->where('owner_user_id', $parent->id)
            ->whereNull('retired_at')
            ->where('name', $name)
            ->exists();
        if ($name === '' || $taken) {
            throw ValidationException::withMessages([
                'name' => [$name === '' ? 'Give the chore a name.' : "You already have a custom chore called \"{$name}\"."],
            ]);
        }

        $difficulty = Difficulty::from($data['difficulty']);
        $template = ChoreTemplate::create([
            'key' => null,
            'name' => $name,
            'description' => trim((string) ($data['description'] ?? '')),
            'icon' => $data['icon'],
            'category' => Catalogue::CUSTOM,
            'location' => $data['location'],
            'min_age' => 4,
            'max_age' => 10,
            'default_points' => match ($difficulty) {
                Difficulty::Easy => 3,
                Difficulty::Medium => 5,
                Difficulty::Hard => 8,
            },
            'difficulty' => $difficulty,
            'has_visible_end_state' => false,
            'verification_class' => null,
            'verification_mode' => ChoreTemplate::MODE_MANUAL,
            'model_class' => null,
            'min_active_seconds' => null,
            'is_custom' => true,
            'owner_user_id' => $parent->id,
        ]);

        return response()->json(['chore' => self::payloadFor($template)], 201);
    }

    public static function payloadFor(ChoreTemplate $t): array
    {
        return [
            'id' => $t->id,
            'key' => $t->key,
            'name' => $t->name,
            'description' => $t->description,
            'icon' => $t->icon,
            'category' => $t->category,
            // Where it usually happens; offered first when a parent assigns it.
            'location' => $t->location,
            'min_age' => $t->min_age,
            'max_age' => $t->max_age,
            'default_points' => $t->default_points,
            'difficulty' => $t->difficulty->value,
            'has_visible_end_state' => $t->has_visible_end_state,
            'model_verifiable' => $t->isModelVerifiable(),
            // Phase 4: lstm when the movement model checks it in the quest
            // session, manual when only the parent does.
            'verification_mode' => $t->verification_mode,
            'model_class' => $t->model_class,
            'min_active_seconds' => $t->min_active_seconds,
            'is_custom' => $t->is_custom,
            'retired' => $t->isRetired(),
        ];
    }

    private function payload(ChoreTemplate $t): array
    {
        return self::payloadFor($t);
    }
}
