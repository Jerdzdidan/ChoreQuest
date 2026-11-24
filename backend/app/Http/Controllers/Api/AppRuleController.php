<?php

namespace App\Http\Controllers\Api;

use App\Domain\AppLock\AppLockInput;
use App\Domain\AppLock\RuleBook;
use App\Http\Controllers\Controller;
use App\Models\AppRule;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Validation\Rule;

/**
 * Which apps are locked on this phone (AL-2).
 *
 * GET /app-rules?device_key=, either identity: the phone reads its own
 * rules, whoever is signed in on it, and keeps a copy so locked apps stay
 * locked when it cannot reach the server.
 *
 * PATCH /app-rules, parent only: set some of this phone's apps to Open,
 * Earned time or Grown-ups only.
 */
class AppRuleController extends Controller
{
    public function __construct(private readonly RuleBook $rules) {}

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate(['device_key' => AppLockInput::deviceKey()]);

        $identity = $request->user();
        $householdId = $identity instanceof User ? $identity->id : $identity->user_id;

        return response()->json(self::payload($data['device_key'], $this->rules->forPhone($householdId, $data['device_key'])));
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_key' => AppLockInput::deviceKey(),
            'rules' => ['required', 'array', 'min:1', 'max:50'],
            'rules.*' => ['required', 'array'],
            'rules.*.package' => [...AppLockInput::package(), 'distinct', Rule::notIn([AppLockInput::OWN_PACKAGE])],
            'rules.*.setting' => ['required', 'string', Rule::in(AppRule::SETTINGS)],
        ], [
            'rules.*.package.not_in' => 'ChoreQuest cannot lock itself.',
        ]);

        /** @var User $parent */
        $parent = $request->user();

        $rules = $this->rules->apply(
            $parent,
            $parent,
            $data['device_key'],
            array_map(fn (array $r) => ['package' => $r['package'], 'setting' => $r['setting']], $data['rules']),
        );

        return response()->json(self::payload($data['device_key'], $rules));
    }

    /** @param  Collection<int, AppRule>  $rules */
    private static function payload(string $deviceKey, Collection $rules): array
    {
        return [
            'device_key' => $deviceKey,
            'rules' => $rules->map(fn (AppRule $r) => $r->toPayload())->values()->all(),
        ];
    }
}
