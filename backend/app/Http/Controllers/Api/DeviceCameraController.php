<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\DeviceCamera;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The cameras a child's phone can see (BE-8): reported by the child's
 * phone, read by the parent's when scheduling a quest.
 */
class DeviceCameraController extends Controller
{
    /**
     * POST /my/cameras (child). The phone's whole list, which replaces
     * whatever was there: a camera missing from it is gone.
     */
    public function store(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'device_key' => ['required', 'string', 'max:100'],
            'cameras' => ['present', 'array', 'max:20'],
            'cameras.*.key' => ['required', 'string', 'max:100', 'distinct'],
            'cameras.*.kind' => ['required', 'string', Rule::in(DeviceCamera::KINDS)],
            'cameras.*.label' => ['required', 'string', 'max:60'],
            'cameras.*.connected' => ['required', 'boolean'],
        ]);

        DB::transaction(function () use ($child, $data) {
            DeviceCamera::where('child_id', $child->id)->delete();
            foreach ($data['cameras'] as $camera) {
                DeviceCamera::create([
                    'child_id' => $child->id,
                    'device_key' => $data['device_key'],
                    'camera_key' => $camera['key'],
                    'kind' => $camera['kind'],
                    'label' => $camera['label'],
                    'connected' => $camera['connected'],
                    'last_seen_at' => now(),
                ]);
            }
        });

        return response()->json(['cameras' => $this->list($child, thirdPartyOnly: false)]);
    }

    /**
     * GET /children/{child}/cameras (parent). The child's third-party
     * cameras that are connected right now, for the Third-party camera
     * option: empty means the option is greyed out.
     */
    public function index(Request $request, Child $child): JsonResponse
    {
        abort_unless($child->user_id === $request->user()->id, 404);

        return response()->json(['cameras' => $this->list($child, thirdPartyOnly: true)]);
    }

    /** @return list<array<string, mixed>> */
    private function list(Child $child, bool $thirdPartyOnly): array
    {
        $query = DeviceCamera::where('child_id', $child->id)->orderBy('label');
        if ($thirdPartyOnly) {
            $query->thirdParty()->connectedAt(now());
        }

        return $query->get()->map(fn (DeviceCamera $camera) => [
            'key' => $camera->camera_key,
            'kind' => $camera->kind,
            'label' => $camera->label,
            'connected' => $camera->connected,
            'last_seen_at' => $camera->last_seen_at->toIso8601String(),
        ])->all();
    }
}
