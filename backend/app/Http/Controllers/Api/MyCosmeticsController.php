<?php

namespace App\Http\Controllers\Api;

use App\Domain\Progress\CosmeticService;
use App\Http\Controllers\Controller;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * A child's own cosmetics. Child token only: a child can read, add to and
 * change their own record, never a brother's or sister's.
 */
class MyCosmeticsController extends Controller
{
    public function __construct(private readonly CosmeticService $cosmetics)
    {
    }

    public function index(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        return response()->json([
            'cosmetics' => $this->cosmetics->owned($child),
        ]);
    }

    /**
     * The app reports what the child's level has unlocked, from its
     * registries; each item is recorded once. Keys are checked for shape
     * only, since the registries, not the server, know which items exist.
     */
    public function store(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'items' => ['required', 'array', 'min:1', 'max:100'],
            'items.*.category' => ['required', 'string', Rule::in(CosmeticService::CATEGORIES)],
            'items.*.key' => ['required', 'string', 'regex:/^[a-z0-9_]{1,40}$/'],
        ]);

        $recorded = $this->cosmetics->recordUnlocked($child, $data['items']);

        return response()->json([
            'unlocked' => $recorded,
            'cosmetics' => $this->cosmetics->owned($child),
        ]);
    }

    /**
     * Put on one item the child owns. Whatever else was on in that category
     * comes off, so at most one item per category is ever on.
     */
    public function update(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'category' => ['required', 'string', Rule::in(CosmeticService::CATEGORIES)],
            'key' => ['required', 'string', 'regex:/^[a-z0-9_]{1,40}$/'],
        ]);

        if (! $this->cosmetics->equip($child, $data['category'], $data['key'])) {
            throw ValidationException::withMessages([
                'key' => ["You haven't unlocked this one yet. Keep doing quests!"],
            ]);
        }

        return response()->json([
            'cosmetics' => $this->cosmetics->owned($child),
        ]);
    }
}
