<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The cameras a child's phone can see (BE-8), as the phone reports them.
 *
 * The parent's phone reads this to offer or grey out "Third-party camera"
 * when scheduling a quest. The child's phone replaces its whole list at app
 * start, on resume and whenever a camera connects or disconnects; a camera
 * not heard from for ten minutes counts as disconnected, so the parent's
 * option greys out by itself when the child's phone goes quiet.
 *
 * - device_key: the phone that reported it.
 * - camera_key: the camera, stable on that phone; what an assignment's
 *   camera_device_id names.
 * - kind: phone (front or back), external (a USB camera the camera plugin
 *   lists) or network (a CCTV or IP camera added by address).
 * - label: what the parent sees, such as "Kitchen CCTV".
 *
 * A network camera's address and login never come here; they stay in the
 * phone's secure storage.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_cameras', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();
            $table->string('device_key', 100);
            $table->string('camera_key', 100);
            $table->string('kind', 10);
            $table->string('label', 60);
            $table->boolean('connected')->default(false);
            $table->timestamp('last_seen_at');
            $table->timestamps();

            $table->unique(['child_id', 'camera_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_cameras');
    }
};
