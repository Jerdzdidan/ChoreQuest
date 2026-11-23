<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The schedule a parent sets for a quest (PS-7), on the child's phone as an
 * alarm.
 *
 * - days_of_week: the ISO weekdays a daily quest repeats on, 1 (Monday) to 7
 *   (Sunday), as a JSON list. Null means every day, so every assignment made
 *   before this column existed keeps appearing daily.
 * - ringtone_key: which alarm sound rings (the app's ringtone registry).
 * - camera_source: phone or external. One-time quests always use the phone.
 * - camera_device_id: which third-party camera, when camera_source is
 *   external.
 * - alarm_enabled: whether the phone rings at due_time at all.
 *
 * The existing due_time becomes the alarm time; only its label in the app
 * changes, from "Finish by" to "Alarm".
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('assignments', function (Blueprint $table) {
            $table->json('days_of_week')->nullable()->after('scheduled_date');
            $table->string('ringtone_key', 30)->default('classic')->after('due_time');
            $table->string('camera_source', 10)->default('phone')->after('ringtone_key');
            $table->string('camera_device_id', 100)->nullable()->after('camera_source');
            $table->boolean('alarm_enabled')->default(true)->after('camera_device_id');
        });
    }

    public function down(): void
    {
        Schema::table('assignments', function (Blueprint $table) {
            $table->dropColumn(['days_of_week', 'ringtone_key', 'camera_source', 'camera_device_id', 'alarm_enabled']);
        });
    }
};
