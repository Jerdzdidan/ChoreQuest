<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\DeviceStatus;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POST /my/device-status (BE-9), child only: the phone's "ready for alarms"
 * checklist (DV-1), when it last copied the schedule (DV-3) and the app
 * version, replacing the last report. The parent's child list carries it,
 * as Ready or Needs setup.
 */
class DeviceStatusController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'checks' => ['required', 'array', 'max:12'],
            'checks.*' => ['boolean'],
            'last_sync_at' => ['nullable', 'date'],
            'app_version' => ['nullable', 'string', 'max:20'],
        ]);

        // Ready means every row of the checklist is green; the phone sends
        // the rows, and the server decides, so the two cannot disagree.
        $checks = array_map('boolval', $data['checks']);
        $status = DeviceStatus::updateOrCreate(['child_id' => $child->id], [
            'checks' => $checks,
            'checklist_passed' => $checks !== [] && ! in_array(false, $checks, true),
            'last_sync_at' => $data['last_sync_at'] ?? null,
            'app_version' => $data['app_version'] ?? null,
            'reported_at' => now(),
        ]);

        return response()->json(['device' => DeviceStatus::summaryFor($status)]);
    }
}
