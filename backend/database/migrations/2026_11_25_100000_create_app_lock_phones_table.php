<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The phones App Lock is turned on for, and how each last said it was
 * (AL-4, rule 10: App Lock never stops silently).
 *
 * A row is made when a parent turns App Lock on, on that phone, and removed
 * when they turn it off there. The phone's watcher reports every 15 minutes
 * and whenever a permission changes: checks holds what it found, by name
 * (usage_access, overlay, notifications, battery), and problems_since when
 * the current stretch of missing permissions began. A phone that stops
 * reporting is noticed from reported_at, so a watcher that was stopped, an
 * uninstalled app or a phone that is off all reach the parent too.
 *
 * ticket_salt makes the phone's report ticket (see PhoneTicket). A new row
 * gets a new salt, so turning App Lock off retires the old ticket.
 *
 * The plan counted five migrations for Phase 5; this sixth one exists
 * because App Lock belongs to a phone, not to a child: a phone may be
 * signed in as a child, a grown-up or no one, so the child's own device
 * status cannot carry it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_lock_phones', function (Blueprint $table) {
            $table->id();
            // The household.
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('device_key', 64);
            // What the parent sees, from the phone: maker and model.
            $table->string('name', 60);
            $table->string('ticket_salt', 32);
            $table->json('checks')->nullable();
            $table->timestamp('problems_since')->nullable();
            $table->timestamp('reported_at')->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'device_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('app_lock_phones');
    }
};
