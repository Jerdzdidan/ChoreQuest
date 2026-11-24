<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which apps are locked on which phone (AL-1).
 *
 * App Lock covers the phone it is set up on, so a rule names that phone
 * (device_key, which the phone makes for itself) as well as the household
 * and the app's package. An app with no row is Open. The setting is
 * earned_time (a child spends earned minutes on it, or a grown-up uses
 * their PIN) or grown_ups_only (a grown-up only).
 *
 * The phone's list of installed apps never comes here: only the packages a
 * parent locked. No minutes either; those stay in ledger_entries.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_rules', function (Blueprint $table) {
            $table->id();
            // The household: its account holder, as for children.
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('device_key', 64);
            $table->string('package', 150);
            $table->string('setting', 20);
            // The grown-up who last set it.
            $table->foreignId('set_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['user_id', 'device_key', 'package']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('app_rules');
    }
};
