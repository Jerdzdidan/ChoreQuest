<?php

namespace App\Http\Controllers\Api;

use App\Domain\AppLock\AppLockInput;
use App\Domain\AppLock\MinuteResult;
use App\Domain\AppLock\ScreenTime;
use App\Http\Controllers\Controller;
use App\Models\AppRule;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POST /screen-time/minutes (AL-2), child only: one minute of an Earned
 * time app, written by the server as a -1 ledger row (rule 9).
 *
 * 201: spent; the phone keeps the app open for one minute. With
 * "opening": true it also records the unlock.
 * 409: no time left; nothing written, the app stays locked.
 * 422: on this phone the app is Open or Grown-ups only; nothing written.
 */
class ScreenTimeController extends Controller
{
    public function __construct(private readonly ScreenTime $screenTime) {}

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_key' => AppLockInput::deviceKey(),
            'package' => AppLockInput::package(),
            'opening' => ['sometimes', 'boolean'],
        ]);

        /** @var Child $child */
        $child = $request->user();

        $result = $this->screenTime->spendMinute(
            $child,
            $data['device_key'],
            $data['package'],
            (bool) ($data['opening'] ?? false),
            $child->localNow(),
        );

        return match ($result->outcome) {
            MinuteResult::SPENT => response()->json([
                'spent_minutes' => 1,
                'balance_minutes' => $result->balanceMinutes,
                'unlock' => $result->unlock?->load('child')->toPayload(),
            ], 201),
            MinuteResult::NO_TIME => response()->json([
                'message' => 'No time left yet. Finish a quest to earn more.',
                'reason' => MinuteResult::NO_TIME,
                'balance_minutes' => $result->balanceMinutes,
            ], 409),
            MinuteResult::NOT_EARNED_TIME => response()->json([
                'message' => $result->setting === AppRule::GROWN_UPS_ONLY
                    ? 'That app is for grown-ups only.'
                    : 'That app is not locked, so it needs no minutes.',
                'reason' => MinuteResult::NOT_EARNED_TIME,
                'setting' => $result->setting,
                'balance_minutes' => $result->balanceMinutes,
            ], 422),
        };
    }
}
