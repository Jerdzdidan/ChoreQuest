<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A parent's 4-digit sign-in PIN (PA-1, rule 6). Optional: null means the
 * parent signs in with email and password only. Five wrong PINs set
 * pin_locked_at, which turns the PIN off until the next email-and-password
 * sign-in; a PIN never resets a password.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('pin_hash')->nullable()->after('password');
            $table->unsignedTinyInteger('pin_failed_attempts')->default(0)->after('pin_hash');
            $table->timestamp('pin_locked_at')->nullable()->after('pin_failed_attempts');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['pin_hash', 'pin_failed_attempts', 'pin_locked_at']);
        });
    }
};
