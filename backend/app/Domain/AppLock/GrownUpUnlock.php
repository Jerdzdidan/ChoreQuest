<?php

namespace App\Domain\AppLock;

use App\Models\AppRule;
use App\Models\AppUnlock;
use App\Models\User;
use Illuminate\Support\Carbon;

/**
 * A grown-up opening a locked app from the lock screen (AL-2, rule 10).
 *
 * The lock screen checks the grown-up through the ordinary PIN sign-in
 * (POST /parent/pin-login, with its five tries), then records the unlock
 * here with the token it was given, and only then opens the app. So the
 * PIN rule lives in one place, and no app opens for a grown-up without a
 * record of who, which app, which phone and when.
 */
class GrownUpUnlock
{
    /**
     * How new the grown-up's token must be: it was issued for this unlock,
     * moments ago. An older token, such as the session a phone has kept
     * all day, is not proof that someone just typed a PIN.
     */
    public const FRESH_SECONDS = 300;

    /** Refused: the token is older than FRESH_SECONDS. */
    public const STALE = 'stale';

    /** Refused: on this phone the app is Open. */
    public const NOT_LOCKED = 'not_locked';

    public function __construct(private readonly RuleBook $rules) {}

    /**
     * $tokenName and $tokenIssuedAt describe the token the request came
     * with. A token from the PIN sign-in is named 'parent-pin' (see
     * AuthController::pinLogin); any other was earned with the password.
     */
    public function record(
        User $parent,
        ?string $tokenName,
        ?Carbon $tokenIssuedAt,
        string $deviceKey,
        string $package,
        Carbon $now,
    ): AppUnlock|string {
        if ($tokenIssuedAt === null || $tokenIssuedAt->lt($now->copy()->subSeconds(self::FRESH_SECONDS))) {
            return self::STALE;
        }

        if ($this->rules->settingFor($parent->id, $deviceKey, $package) === AppRule::OPEN) {
            return self::NOT_LOCKED;
        }

        return AppUnlock::create([
            'user_id' => $parent->id,
            'device_key' => $deviceKey,
            'package' => $package,
            'method' => $tokenName === 'parent-pin' ? AppUnlock::PARENT_PIN : AppUnlock::PARENT_PASSWORD,
            'parent_id' => $parent->id,
        ]);
    }
}
