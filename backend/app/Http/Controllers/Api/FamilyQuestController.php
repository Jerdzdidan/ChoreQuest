<?php

namespace App\Http\Controllers\Api;

use App\Domain\Family\FamilyQuestService;
use App\Http\Controllers\Controller;
use App\Models\FamilyQuest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * The household's shared quests (F2): a parent sets one up, and both sides of
 * the app read how far the household has come.
 *
 * Nothing here writes screen time. The minutes go out through the approval
 * flow when the target is reached (F3).
 */
class FamilyQuestController extends Controller
{
    public function __construct(private readonly FamilyQuestService $quests)
    {
    }

    /** Every quest of this household, the newest window first. */
    public function index(Request $request): JsonResponse
    {
        $parent = $request->user();
        $quests = $parent->familyQuests()->orderByDesc('ends_at')->orderByDesc('id')->limit(50)->get();
        $today = $parent->localNow();
        $names = $parent->children()->pluck('name', 'id');

        return response()->json([
            'family_quests' => $quests
                ->map(fn (FamilyQuest $quest) => self::payloadFor($quest, $this->quests, $today, $names))
                ->all(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $parent = $request->user();

        $data = $request->validate([
            'title' => ['required', 'string', 'max:80'],
            'target_count' => ['required', 'integer', 'min:1', 'max:200'],
            'reward_minutes_each' => ['required', 'integer', 'min:0', 'max:600'],
            'starts_at' => ['required', 'date_format:Y-m-d'],
            'ends_at' => ['required', 'date_format:Y-m-d', 'after_or_equal:starts_at'],
        ]);

        $quest = $parent->familyQuests()->create($data);

        return response()->json([
            'family_quest' => self::payloadFor(
                $quest,
                $this->quests,
                $parent->localNow(),
                $parent->children()->pluck('name', 'id'),
            ),
        ], 201);
    }

    /**
     * Calls a quest off. Its contributions go with it; any reward already
     * paid stays in the ledger, which is append-only.
     */
    public function destroy(Request $request, FamilyQuest $familyQuest): JsonResponse
    {
        abort_unless($familyQuest->user_id === $request->user()->id, 404);

        $familyQuest->delete();

        return response()->json(status: 204);
    }

    /**
     * One quest as both sides of the app read it. [$names] maps child ids to
     * names, so a child's own app can say who helped without another request.
     *
     * @param  Collection<int, string>  $names
     * @return array<string, mixed>
     */
    public static function payloadFor(
        FamilyQuest $quest,
        FamilyQuestService $service,
        Carbon $today,
        Collection $names,
    ): array {
        $progress = $service->progress($quest);

        return [
            'id' => $quest->id,
            'title' => $quest->title,
            'target_count' => $quest->target_count,
            'reward_minutes_each' => $quest->reward_minutes_each,
            'starts_at' => $quest->starts_at->toDateString(),
            'ends_at' => $quest->ends_at->toDateString(),
            'done' => $progress['done'],
            'reached' => $progress['reached'],
            'rewarded_at' => $quest->rewarded_at?->toIso8601String(),
            'state' => $service->state($quest, $today, $progress['reached']),
            'helpers' => array_map(
                fn (array $helper) => [
                    'child_id' => $helper['child_id'],
                    'name' => $names[$helper['child_id']] ?? 'A child',
                    'quests' => $helper['quests'],
                ],
                $progress['helpers'],
            ),
        ];
    }
}
