<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Parents are the only account holders. The household code is what a child
     * device is paired with once, so a child can sign in without an email.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('household_code', 8)->unique()->after('email');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('household_code');
        });
    }
};
