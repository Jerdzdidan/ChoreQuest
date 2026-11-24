<?php

namespace App\Http\Controllers\Api;

use App\Domain\AppLock\AppLockInput;
use App\Domain\AppLock\GrownUpUnlock;
use App\Http\Controllers\Controller;
use App\Models\AppUnlock;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * The record of locked apps opened from the lock screen (AL-2, rule 10).
 *
 * POST /app-unlocks, parent only: a grown-up opening a locked app, with
 * the token their PIN sign-in just gave them. The phone opens the app only
 * once this answers 201.
 *
 * GET /app-unlocks, parent only: the household's record, newest first,
 * children's openings and grown-ups' alike. ?device_key= narrows it to one
 * phone.
 */
class AppUnlockController extends Controller
{
    public function __construct(private readonly GrownUpUnlock $grownUps) {}

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_key' => AppLockInput::deviceKey(),
            'package' => AppLockInput::package(),
        ]);

        /** @var User $parent */
        $parent = $request->user();
        $token = $parent->currentAccessToken();
        $token = $token instanceof PersonalAccessToken ? $token : null;

        $result = $this->grownUps->record(
            $parent,
            $token?->name,
            $token?->created_at,
            $data['device_key'],
            $data['package'],
            now(),
        );

        return match ($result) {
            GrownUpUnlock::STALE => response()->json([
                'message' => 'Type your PIN again to open this app.',
            ], 423),
            GrownUpUnlock::NOT_LOCKED => response()->json([
                'message' => 'That app is not locked on this phone.',
            ], 422),
            default => response()->json(['unlock' => $result->load('parent')->toPayload()], 201),
        };
    }

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_key' => ['nullable', 'string', 'regex:'.AppLockInput::DEVICE_KEY_PATTERN],
        ]);

        $unlocks = AppUnlock::where('user_id', $request->user()->id)
            ->when($data['device_key'] ?? null, fn ($q, string $key) => $q->where('device_key', $key))
            ->with(['child', 'parent'])
            ->orderByDesc('id')
            ->limit(200)
            ->get();

        return response()->json([
            'unlocks' => $unlocks->map(fn (AppUnlock $u) => $u->toPayload())->all(),
        ]);
    }
}
