<?php

namespace App\Http\Controllers\Api;

use App\Domain\AppLock\AppLockInput;
use App\Domain\AppLock\PhoneHealth;
use App\Http\Controllers\Controller;
use App\Models\AppLockPhone;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * The phones App Lock is on for (AL-4, rule 10).
 *
 * Parent only:
 * - GET /app-lock/phones: each phone and whether App Lock is working there.
 * - PUT /app-lock/phones {device_key, name}: turning App Lock on, on this
 *   phone. Answers with the ticket the phone's watcher reports with.
 * - DELETE /app-lock/phones?device_key=: turning it off there.
 *
 * The phone's watcher, with no one signed in:
 * - POST /app-lock/status {household_id, device_key, ticket, checks}: what
 *   it found, every 15 minutes and whenever a permission changes.
 */
class AppLockPhoneController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $now = now();

        return response()->json([
            'phones' => AppLockPhone::where('user_id', $request->user()->id)
                ->orderBy('name')
                ->get()
                ->map(fn (AppLockPhone $phone) => $phone->toPayload($now))
                ->all(),
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_key' => AppLockInput::deviceKey(),
            'name' => ['required', 'string', 'max:60'],
        ]);

        /** @var User $parent */
        $parent = $request->user();

        // A phone turned on again keeps its row and its ticket; only turning
        // it off retires the ticket.
        $phone = AppLockPhone::firstOrCreate(
            ['user_id' => $parent->id, 'device_key' => $data['device_key']],
            ['name' => $data['name'], 'ticket_salt' => Str::random(32)],
        );
        if ($phone->name !== $data['name']) {
            $phone->forceFill(['name' => $data['name']])->save();
        }

        return response()->json([
            'phone' => $phone->toPayload(now()),
            'phone_ticket' => $phone->ticket(),
        ], $phone->wasRecentlyCreated ? 201 : 200);
    }

    public function destroy(Request $request): JsonResponse
    {
        $data = $request->validate(['device_key' => AppLockInput::deviceKey()]);

        AppLockPhone::where('user_id', $request->user()->id)
            ->where('device_key', $data['device_key'])
            ->delete();

        return response()->json(['message' => 'App Lock is off on this phone.']);
    }

    public function status(Request $request): JsonResponse
    {
        $data = $request->validate([
            'household_id' => ['required', 'integer'],
            'device_key' => AppLockInput::deviceKey(),
            'ticket' => ['required', 'string', 'max:100'],
            'checks' => ['required', 'array'],
            ...collect(PhoneHealth::CHECKS)->mapWithKeys(fn (string $name) => ["checks.$name" => ['required', 'boolean']])->all(),
        ]);

        $phone = AppLockPhone::where('user_id', $data['household_id'])
            ->where('device_key', $data['device_key'])
            ->first();

        // One answer for a phone App Lock is not on for and a wrong ticket.
        // Either way the watcher stops: nothing it says is being heard.
        if (! $phone || ! $phone->ticketMatches($data['ticket'])) {
            return response()->json([
                'message' => 'App Lock is not on for this phone.',
                'app_lock' => 'off',
            ], 403);
        }

        $now = now();
        $checks = collect(PhoneHealth::CHECKS)->mapWithKeys(fn (string $name) => [$name => (bool) $data['checks'][$name]])->all();
        $phone->forceFill([
            'checks' => $checks,
            'reported_at' => $now,
            'problems_since' => PhoneHealth::problemsSinceAfter($checks, $phone->problems_since, $now),
        ])->save();

        return response()->json(['app_lock' => 'on', 'phone' => $phone->toPayload($now)]);
    }
}
