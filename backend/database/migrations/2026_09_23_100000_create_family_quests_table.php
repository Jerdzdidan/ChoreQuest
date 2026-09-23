<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('family_quests', function (Blueprint $table) {
            $table->id();

            // The household, which in this schema is the parent: children
            // hang off the same user (F1).
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();

            $table->string('title');

            // How many approved quests the household needs between them.
            $table->unsignedSmallInteger('target_count');

            // What each child who helped receives when the target is reached.
            $table->unsignedSmallInteger('reward_minutes_each');

            // The window, in the household's own days, like for_date.
            $table->date('starts_at');
            $table->date('ends_at');

            // When the target was reached and the minutes went out. Null
            // until then; set once, so nobody is paid twice.
            $table->timestamp('rewarded_at')->nullable();

            $table->timestamps();

            $table->index(['user_id', 'ends_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('family_quests');
    }
};
