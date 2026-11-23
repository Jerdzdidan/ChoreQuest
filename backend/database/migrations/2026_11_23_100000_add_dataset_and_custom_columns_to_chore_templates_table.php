<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What Phase 4's catalogue needs on each chore (CH-3).
 *
 * - key: the chore's key in ml/chore_manifest.json, which the seeder
 *   updates or creates by. Null for a parent's custom chore.
 * - verification_mode: lstm when the movement model checks the chore, manual
 *   when only the parent does. Manual is the default, the safe one.
 * - model_class: the model's class for an lstm chore, null otherwise.
 * - min_active_seconds: seconds of matching movement before Done appears,
 *   until the model config (BE-6) names its own.
 * - is_custom and owner_user_id: a chore a parent made up, seen only by that
 *   parent.
 * - retired_at: a chore taken out of the catalogue. Never deleted:
 *   assignments and submissions cascade-delete with their template, so a
 *   retired chore keeps its history and its existing assignments.
 *
 * Existing columns are untouched; has_visible_end_state and
 * verification_class stay for the rows that use them.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('chore_templates', function (Blueprint $table) {
            $table->string('key', 60)->nullable()->unique()->after('id');
            $table->string('verification_mode', 10)->default('manual')->after('verification_class');
            $table->unsignedSmallInteger('model_class')->nullable()->after('verification_mode');
            $table->unsignedSmallInteger('min_active_seconds')->nullable()->after('model_class');
            $table->boolean('is_custom')->default(false)->after('min_active_seconds');
            $table->foreignId('owner_user_id')->nullable()->after('is_custom')
                ->constrained('users')->cascadeOnDelete();
            $table->timestamp('retired_at')->nullable()->after('owner_user_id');
        });
    }

    public function down(): void
    {
        Schema::table('chore_templates', function (Blueprint $table) {
            $table->dropConstrainedForeignId('owner_user_id');
            $table->dropUnique(['key']);
            $table->dropColumn(['key', 'verification_mode', 'model_class', 'min_active_seconds', 'is_custom', 'retired_at']);
        });
    }
};
