<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Every time a locked app was opened from the lock screen (AL-1, rule 10):
 * who, which app, on which phone, when, and how.
 *
 * - child_minutes: a child opened an Earned time app with their minutes.
 *   child_id says who. The minutes themselves are -1 rows in
 *   ledger_entries, one a minute, with the package in the note.
 * - parent_pin, parent_password: a grown-up opened it, after their PIN or,
 *   with the PIN off, their password. parent_id says who.
 *
 * Append-only, like the ledger: no updated_at, nothing here is changed or
 * removed, so a grown-up unlock cannot be taken back out of the record.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_unlocks', function (Blueprint $table) {
            $table->id();
            // The household.
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('device_key', 64);
            $table->string('package', 150);
            $table->string('method', 20);
            $table->foreignId('child_id')->nullable()->constrained()->cascadeOnDelete();
            $table->foreignId('parent_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('app_unlocks');
    }
};
