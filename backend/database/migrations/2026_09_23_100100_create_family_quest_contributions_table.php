<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('family_quest_contributions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('family_quest_id')->constrained()->cascadeOnDelete();
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();

            // The approved photo behind it. Deleting the photo removes the
            // contribution with it, so progress can never outlive its proof.
            $table->foreignId('submission_id')->constrained()->cascadeOnDelete();

            $table->timestamps();

            // One contribution per photo per quest, enforced by the database
            // rather than by a check in application code, the way the ledger
            // guards one earning per submission.
            $table->unique(['family_quest_id', 'submission_id']);
            $table->index(['family_quest_id', 'child_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('family_quest_contributions');
    }
};
