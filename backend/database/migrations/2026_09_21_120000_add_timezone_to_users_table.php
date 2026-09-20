<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The household's timezone, an IANA name such as Asia/Manila. A household is
 * its parent's account, so the column lives on users.
 *
 * Days (a quest's date, streaks, the daily and weekly limits) follow it rather
 * than the server's UTC. Every existing household starts on Asia/Manila, where
 * the study's families are; the app replaces it with the phone's own timezone
 * when someone signs in.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('timezone', 64)->default('Asia/Manila')->after('household_code');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('timezone');
        });
    }
};
