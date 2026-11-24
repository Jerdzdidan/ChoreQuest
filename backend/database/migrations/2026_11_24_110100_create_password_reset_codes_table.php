<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The 6-digit codes that reset a forgotten password (PA-1, PA-3). Only a
 * hash of each code is kept. A code lasts 15 minutes and allows 5 tries;
 * used_at is set when it changes a password, so it works once.
 *
 * Laravel's own password_reset_tokens table holds link tokens, one per
 * email with no tries counted, so it is left alone.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('password_reset_codes', function (Blueprint $table) {
            $table->id();
            $table->string('email')->index();
            $table->string('code_hash');
            // useCurrent so MariaDB 10.4 does not make it ON UPDATE
            // CURRENT_TIMESTAMP, which would push the expiry back at every
            // wrong try. Always set when a code is made.
            $table->timestamp('expires_at')->useCurrent();
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->timestamp('used_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('password_reset_codes');
    }
};
