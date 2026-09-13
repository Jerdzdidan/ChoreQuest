<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * One row per child. Holds every number the allocation engine reads, and
     * both confidence thresholds -- so a parent can retune the model's
     * behaviour without a rebuild.
     */
    public function up(): void
    {
        Schema::create('allocation_rules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->unique()->constrained()->cascadeOnDelete();

            $table->unsignedSmallInteger('minutes_per_point')->default(5);
            $table->unsignedSmallInteger('daily_cap_minutes')->default(60);
            $table->unsignedSmallInteger('weekly_cap_minutes')->default(300);

            // At or above `confidence_high` the submission is auto-approved.
            // At or below `confidence_low` it is auto-rejected.
            // Anything between the two is the abstention band and goes to the parent.
            $table->decimal('confidence_high', 4, 3)->default(0.850);
            $table->decimal('confidence_low', 4, 3)->default(0.400);

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('allocation_rules');
    }
};
