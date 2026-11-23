<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * MariaDB gives the first NOT NULL timestamp of a table an unasked-for
 * ON UPDATE CURRENT_TIMESTAMP, so device_cameras.last_seen_at would move to
 * "now" whenever anything else in the row changed, and a camera the phone
 * had stopped reporting could look freshly seen. Only the phone's own
 * report may move it. The column is redefined with its default and without
 * that clause; every value stays as it is.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('device_cameras', function (Blueprint $table) {
            $table->timestamp('last_seen_at')->useCurrent()->change();
        });
    }

    public function down(): void
    {
        // Nothing to restore: the clause was never wanted.
    }
};
