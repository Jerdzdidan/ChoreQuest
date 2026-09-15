<?php

namespace App\Domain\Progress;

use App\Models\Child;
use App\Models\ChildCosmetic;
use Illuminate\Support\Facades\DB;

/**
 * The cosmetics each child has unlocked: outfits, headwear, pets and room
 * items.
 *
 * Unlock levels live in the app's registries, next to the level thresholds
 * in lib/shared/leveling.dart, and are not repeated here. That is the call
 * G10 made for animals: cosmetics change how a child's character looks,
 * never how minutes are worked out, so the app decides what a level unlocks
 * and reports it, and this class records each item once. Nothing here is
 * random, nothing is bought, and nothing touches the ledger or badges.
 */
class CosmeticService
{
    /**
     * What a cosmetic slots into. Each room slot is its own category, so a
     * rug, a picture and a plant can all be on at once.
     */
    public const CATEGORIES = ['outfit', 'headwear', 'pet', 'rug', 'wall', 'plant'];

    /**
     * Records items as unlocked for this child.
     *
     * Safe to repeat. The unique index on (child_id, category, item_key)
     * makes an item already held a no-op, which also leaves whether it is on
     * exactly as it was.
     *
     * @param  list<array{category: string, key: string}>  $items
     * @return list<array{category: string, key: string}> the items this call newly recorded
     */
    public function recordUnlocked(Child $child, array $items): array
    {
        $recorded = [];

        foreach ($items as $item) {
            $inserted = DB::table('child_cosmetics')->insertOrIgnore([
                'child_id' => $child->id,
                'category' => $item['category'],
                'item_key' => $item['key'],
                'unlocked_at' => now(),
            ]);

            if ($inserted > 0) {
                $recorded[] = ['category' => $item['category'], 'key' => $item['key']];
            }
        }

        return $recorded;
    }

    /**
     * Everything the child has unlocked, oldest first.
     *
     * @return list<array{category: string, key: string, unlocked_at: string, equipped: bool}>
     */
    public function owned(Child $child): array
    {
        return $child->cosmetics()
            ->orderBy('id')
            ->get()
            ->map(fn (ChildCosmetic $cosmetic) => [
                'category' => $cosmetic->category,
                'key' => $cosmetic->item_key,
                'unlocked_at' => $cosmetic->unlocked_at->toIso8601String(),
                'equipped' => $cosmetic->equipped,
            ])
            ->all();
    }
}
