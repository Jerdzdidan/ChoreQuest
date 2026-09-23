<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('ledger_entries', function (Blueprint $table) {
            // Set on a 'family_reward' row, null on every other kind. The
            // ledger stays append-only; this only says which shared quest a
            // row came from.
            $table->foreignId('family_quest_id')->nullable()->after('submission_id')
                ->constrained()->nullOnDelete();

            // One reward per child per shared quest, enforced by the database,
            // the way one earning per submission already is. Two approvals
            // landing at the same moment cannot pay the same child twice.
            $table->unique(['family_quest_id', 'child_id']);
        });
    }

    public function down(): void
    {
        Schema::table('ledger_entries', function (Blueprint $table) {
            $table->dropUnique(['family_quest_id', 'child_id']);
            $table->dropConstrainedForeignId('family_quest_id');
        });
    }
};
