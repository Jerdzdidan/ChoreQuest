<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Whether a child's phone is ready to ring (BE-9): the "ready for alarms"
 * checklist it ran (DV-1), when it last copied the schedule (DV-3), and the
 * app version. One row per child, replaced at every report, so the parent's
 * Board can say Ready or Needs setup.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_statuses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->unique()->constrained()->cascadeOnDelete();
            $table->boolean('checklist_passed')->default(false);
            // Each checklist row by name, true when it is green.
            $table->json('checks')->nullable();
            $table->timestamp('last_sync_at')->nullable();
            $table->string('app_version', 20)->nullable();
            $table->timestamp('reported_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_statuses');
    }
};
