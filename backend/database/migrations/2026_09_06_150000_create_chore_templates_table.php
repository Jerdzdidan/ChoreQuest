<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chore_templates', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('description');
            $table->string('icon', 40);
            $table->string('category', 40);
            $table->unsignedTinyInteger('min_age');
            $table->unsignedTinyInteger('max_age');
            $table->unsignedSmallInteger('default_points');

            // Can a single photograph show that this chore is finished? This is
            // the scoping flag from Chapter 1: chores that cannot be captured in
            // one image are outside the verification feature entirely.
            $table->boolean('has_visible_end_state')->default(false);

            // Which trained class handles this chore, or null when no class does.
            // Distinct from the flag above: a chore may be photographable in
            // principle while the model has not been trained for it, in which
            // case every submission goes to the parent. Only three classes are
            // trained in Phase 5 -- made bed, cleared table, swept floor.
            $table->string('verification_class', 40)->nullable();

            $table->timestamps();

            $table->index(['min_age', 'max_age']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chore_templates');
    }
};
