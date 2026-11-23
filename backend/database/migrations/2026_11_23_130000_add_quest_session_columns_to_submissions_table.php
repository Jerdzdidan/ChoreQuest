<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What a live quest session sends (BE-1): a Before photo beside the After one
 * (photo_path), and the session's evidence summary.
 *
 * - before_photo_path: private storage, served only through the parent route.
 * - evidence: the summary the phone builds (LS-8), no pictures in it.
 * - session_started_at, session_done_at: when the child tapped Start and Done.
 * - active_seconds: seconds of movement that matched the chore.
 * - verification_mode: lstm or manual for a session; legacy_photo for every
 *   row from before sessions, so old rows read exactly as they did.
 * - camera_source: the camera the session used.
 *
 * Every new row is still a submission, the table XP, streaks, badges, family
 * quests and the ledger already read, so none of that changes.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('submissions', function (Blueprint $table) {
            $table->string('before_photo_path')->nullable()->after('photo_path');
            $table->json('evidence')->nullable()->after('inference_ms');
            $table->timestamp('session_started_at')->nullable()->after('evidence');
            $table->timestamp('session_done_at')->nullable()->after('session_started_at');
            $table->unsignedSmallInteger('active_seconds')->nullable()->after('session_done_at');
            $table->string('verification_mode', 15)->default('legacy_photo')->after('active_seconds');
            $table->string('camera_source', 10)->nullable()->after('verification_mode');
        });
    }

    public function down(): void
    {
        Schema::table('submissions', function (Blueprint $table) {
            $table->dropColumn([
                'before_photo_path', 'evidence', 'session_started_at', 'session_done_at',
                'active_seconds', 'verification_mode', 'camera_source',
            ]);
        });
    }
};
