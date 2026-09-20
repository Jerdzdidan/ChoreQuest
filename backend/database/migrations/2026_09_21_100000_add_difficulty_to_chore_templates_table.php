<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * How hard a chore is: easy, medium or hard. XP for an approved quest follows
 * from it (App\Domain\Progress\Difficulty).
 *
 * Every existing chore is filled in from its default points, the catalogue's
 * own measure of effort: 3 or fewer is easy, 4 or 5 medium, 6 or more hard.
 * The numbers are written out here rather than read from app code, so this
 * migration means the same thing however the code changes later.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('chore_templates', function (Blueprint $table) {
            $table->string('difficulty', 10)->default('easy')->after('default_points');
        });

        DB::table('chore_templates')->update([
            'difficulty' => DB::raw("CASE WHEN default_points <= 3 THEN 'easy' WHEN default_points <= 5 THEN 'medium' ELSE 'hard' END"),
        ]);
    }

    public function down(): void
    {
        Schema::table('chore_templates', function (Blueprint $table) {
            $table->dropColumn('difficulty');
        });
    }
};
