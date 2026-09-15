<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The cosmetics each child has unlocked, and which one of each kind they have
 * on. The badges_earned idea generalised to every cosmetic category.
 *
 * Cosmetic only: nothing here is read when screen time is worked out.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('child_cosmetics', function (Blueprint $table) {
            $table->id();

            // Removing a child's profile removes their cosmetics with it.
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();

            // outfit, headwear, pet, or a room slot: rug, wall, plant. Each
            // room slot is its own category, so one item can be on in each.
            $table->string('category', 20);

            // A key from the app's registry, such as 'space_suit'. The server
            // stores only the key; the app draws the item.
            $table->string('item_key', 40);

            $table->timestamp('unlocked_at')->useCurrent();

            // At most one per child and category, kept so by the equip
            // endpoint inside a transaction.
            $table->boolean('equipped')->default(false);

            // Each item unlocks at most once per child, enforced by the
            // database, as badges_earned does for badges.
            $table->unique(['child_id', 'category', 'item_key']);

            $table->index(['child_id', 'category', 'equipped']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('child_cosmetics');
    }
};
