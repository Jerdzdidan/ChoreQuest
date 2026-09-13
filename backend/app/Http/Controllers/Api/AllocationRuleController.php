<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AllocationRule;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * The parent's screen-time rules for one child: the exchange rate, the two
 * caps, and the two confidence thresholds.
 */
class AllocationRuleController extends Controller
{
    public function show(Request $request, Child $child): JsonResponse
    {
        $this->authoriseOwnership($request, $child);

        return response()->json(['rule' => $this->payload($child->rule())]);
    }

    public function update(Request $request, Child $child): JsonResponse
    {
        $this->authoriseOwnership($request, $child);

        $data = $request->validate([
            'minutes_per_point' => ['sometimes', 'integer', 'min:1', 'max:120'],
            'daily_cap_minutes' => ['sometimes', 'integer', 'min:0', 'max:1440'],
            'weekly_cap_minutes' => ['sometimes', 'integer', 'min:0', 'max:10080'],
            'confidence_high' => ['sometimes', 'numeric', 'between:0,1'],
            'confidence_low' => ['sometimes', 'numeric', 'between:0,1'],
        ]);

        $rule = $child->rule();

        // Validate the rule as it will be after the change, not as it is now:
        // a partial PATCH can break a pairwise invariant even when each field
        // is individually valid.
        $merged = [
            'daily_cap_minutes' => $data['daily_cap_minutes'] ?? $rule->daily_cap_minutes,
            'weekly_cap_minutes' => $data['weekly_cap_minutes'] ?? $rule->weekly_cap_minutes,
            'confidence_high' => $data['confidence_high'] ?? $rule->confidence_high,
            'confidence_low' => $data['confidence_low'] ?? $rule->confidence_low,
        ];

        // The abstention band must exist. Collapsing or inverting it would
        // remove the parent from the loop entirely, which the design forbids.
        if ((float) $merged['confidence_low'] >= (float) $merged['confidence_high']) {
            throw ValidationException::withMessages([
                'confidence_low' => ['The lower threshold must sit below the upper one, so that uncertain submissions still reach you.'],
            ]);
        }

        // A weekly cap under the daily one makes the daily figure a lie.
        if ((int) $merged['weekly_cap_minutes'] < (int) $merged['daily_cap_minutes']) {
            throw ValidationException::withMessages([
                'weekly_cap_minutes' => ['The weekly limit cannot be lower than the daily limit.'],
            ]);
        }

        $rule->update($data);

        return response()->json(['rule' => $this->payload($rule->fresh())]);
    }

    private function authoriseOwnership(Request $request, Child $child): void
    {
        abort_unless($child->user_id === $request->user()->id, 404);
    }

    private function payload(AllocationRule $rule): array
    {
        return [
            'child_id' => $rule->child_id,
            'minutes_per_point' => $rule->minutes_per_point,
            'daily_cap_minutes' => $rule->daily_cap_minutes,
            'weekly_cap_minutes' => $rule->weekly_cap_minutes,
            'confidence_high' => $rule->confidence_high,
            'confidence_low' => $rule->confidence_low,
        ];
    }
}
