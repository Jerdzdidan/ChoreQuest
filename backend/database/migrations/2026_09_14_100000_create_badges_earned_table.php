<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Badges a child has earned. Motivational only: nothing here is read when
 * screen time is worked out, and the ledger stays the only record of minutes.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('badges_earned', function (Blueprint $table) {
            $table->id();

            // Removing a child's profile removes their badges with it.
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();

            // A key such as 'first_quest'. The server stores only the key; the
            // app draws the badge, so artwork and wording can change without
            // a migration.
            $table->string('badge_key', 40);

            $table->timestamp('earned_at')->useCurrent();

            // Each badge at most once per child, enforced by the database
            // rather than by a check in application code, so two approvals
            // landing at the same moment cannot award it twice.
            $table->unique(['child_id', 'badge_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('badges_earned');
    }
};
