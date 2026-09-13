<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The screen-time ledger. Append-only: nothing here is ever updated or
     * deleted, and the balance is always SUM(minutes) rather than a column
     * anyone can overwrite. A mistake is corrected by appending a compensating
     * entry, which leaves the original visible.
     *
     * That is what makes the reliability claim in Chapter 2 checkable: the
     * whole history can be replayed and must produce the same balance.
     *
     * Note the absence of updated_at. There is no update path by design.
     */
    public function up(): void
    {
        Schema::create('ledger_entries', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();

            // Null for consumption and for manual adjustments.
            $table->foreignId('submission_id')->nullable()->constrained()->nullOnDelete();

            // earned | consumed | reversal | adjustment
            $table->string('entry_type', 20);

            // Signed. Positive adds screen time, negative removes it.
            $table->integer('minutes');

            // The workings behind an 'earned' row, kept so a parent can be
            // shown why a child received less than the chore was worth.
            $table->unsignedSmallInteger('points')->nullable();
            $table->unsignedSmallInteger('minutes_gross')->nullable();
            $table->unsignedSmallInteger('minutes_forfeited')->nullable();

            // The day this counts against for the daily cap. Taken from the
            // submission, not from the moment of approval, so a chore keeps
            // the day it was actually done.
            $table->date('for_date');

            $table->string('note')->nullable();

            $table->timestamp('created_at')->useCurrent();

            $table->index(['child_id', 'for_date']);
            $table->index(['child_id', 'entry_type']);

            // One earning per submission and one reversal per submission,
            // enforced by the database rather than by a check in application
            // code. Two parents tapping approve at the same moment cannot
            // credit the same chore twice.
            $table->unique(['submission_id', 'entry_type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ledger_entries');
    }
};
