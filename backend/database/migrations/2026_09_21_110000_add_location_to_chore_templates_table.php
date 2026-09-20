<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Where in a home each catalogue chore usually happens: kitchen, bedroom,
 * study, outdoor or other. It is offered first when a parent assigns the
 * chore; the assignment's own location (U11) is what the child's map uses, so
 * a parent can still place it anywhere.
 *
 * Existing chores are filled in from their category and icon. The catalogue
 * seeder then sets each chore's location exactly.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('chore_templates', function (Blueprint $table) {
            $table->string('location', 20)->default('other')->after('category');
        });

        DB::table('chore_templates')->update([
            'location' => DB::raw(
                "CASE
                    WHEN category = 'kitchen' THEN 'kitchen'
                    WHEN category = 'bedroom' OR icon IN ('wardrobe', 'toys', 'basket') THEN 'bedroom'
                    WHEN icon = 'books' THEN 'study'
                    WHEN icon IN ('plant', 'laundry', 'trash', 'broom') THEN 'outdoor'
                    ELSE 'other'
                END"
            ),
        ]);
    }

    public function down(): void
    {
        Schema::table('chore_templates', function (Blueprint $table) {
            $table->dropColumn('location');
        });
    }
};
