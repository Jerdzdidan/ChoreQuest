<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\ChoreTemplate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ChoreTemplateController extends Controller
{
    /**
     * The catalogue a parent browses. Pass ?child_id= to see only what suits
     * that child's age -- which is the normal way the app calls this.
     */
    public function index(Request $request): JsonResponse
    {
        $query = ChoreTemplate::query()->orderBy('min_age')->orderBy('name');

        if ($request->filled('child_id')) {
            $child = $request->user()->children()->find($request->integer('child_id'));
            abort_unless($child, 404);
            $query->forAge($child->age());
        }

        return response()->json([
            'chores' => $query->get()->map(fn (ChoreTemplate $t) => $this->payload($t))->all(),
        ]);
    }

    public static function payloadFor(ChoreTemplate $t): array
    {
        return [
            'id' => $t->id,
            'name' => $t->name,
            'description' => $t->description,
            'icon' => $t->icon,
            'category' => $t->category,
            'min_age' => $t->min_age,
            'max_age' => $t->max_age,
            'default_points' => $t->default_points,
            'has_visible_end_state' => $t->has_visible_end_state,
            'model_verifiable' => $t->isModelVerifiable(),
        ];
    }

    private function payload(ChoreTemplate $t): array
    {
        return self::payloadFor($t);
    }
}
