<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Things that happened to a quest alarm that the parent must hear about,
 * each one a notification:
 *
 * - override: a grown-up stopped it with their password (BE-10, DV-7b).
 *   Recorded so a grown-up stop can never be used quietly.
 * - timed_out: it rang for the longest allowed time and stopped by itself;
 *   the quest counts as missed, with no penalty (DV-7a).
 * - camera_missing: the scheduled third-party camera was not connected, so
 *   the quest used the phone camera (DV-12).
 *
 * The plan names an alarm_overrides table; the other two kinds have the same
 * shape and reach the parent the same way, so they share it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('alarm_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();
            $table->foreignId('assignment_id')->nullable()->constrained()->nullOnDelete();
            $table->string('kind', 20);
            $table->timestamps();

            $table->index(['child_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('alarm_events');
    }
};
