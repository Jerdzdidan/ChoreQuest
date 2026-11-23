<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A quest session records the chore the model was watching for in
 * model_label (BE-2): its manifest key, which can run to 25 characters
 * ("put_clothes_in_the_hamper") where the column held 20. Widened, never
 * narrowed, so every value already there still fits.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('submissions', function (Blueprint $table) {
            $table->string('model_label', 60)->nullable()->change();
        });
    }

    public function down(): void
    {
        // Narrowing could cut a value short, so the wider column stays.
    }
};
