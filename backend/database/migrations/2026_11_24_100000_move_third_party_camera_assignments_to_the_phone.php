<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * CAM-1: the phone's back camera is the only camera now. Quests scheduled
 * with a USB, CCTV or network camera move to the phone, and forget which
 * camera they had. The columns, and the device_cameras table, stay: the
 * history is evidence.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('assignments')
            ->where('camera_source', '!=', 'phone')
            ->update(['camera_source' => 'phone', 'camera_device_id' => null]);
    }

    /**
     * Which camera each quest had is gone, so there is nothing to put back.
     */
    public function down(): void {}
};
