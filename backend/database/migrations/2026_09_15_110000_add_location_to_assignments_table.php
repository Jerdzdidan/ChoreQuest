<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where in the home an assigned chore happens, so the child's quest map can
 * group quests by place: kitchen, bedroom, study, outdoor, or other.
 *
 * Set per assignment, like points, because the same chore can happen in
 * different places in different homes. Every existing assignment becomes
 * "other" and keeps working exactly as before.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('assignments', function (Blueprint $table) {
            $table->string('location', 20)->default('other')->after('scheduled_date');
        });
    }

    public function down(): void
    {
        Schema::table('assignments', function (Blueprint $table) {
            $table->dropColumn('location');
        });
    }
};
