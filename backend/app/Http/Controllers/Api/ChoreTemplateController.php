<?php

namespace App\Http\Controllers\Api;

use App\Domain\Chores\Catalogue;
use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\ChoreTemplate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

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
