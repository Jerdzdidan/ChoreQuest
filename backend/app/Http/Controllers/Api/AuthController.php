<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Parent-user authentication. Issues tokens carrying the `parent` ability
 * only, whether the parent typed their password or their PIN (rule 6).
 */
class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            // The optional "Set a 4-digit PIN" step (PA-6).
            'pin' => ['nullable', 'digits:4'],
        ]);

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => $data['password'],
            'household_code' => User::generateHouseholdCode(),
        ]);

        if (isset($data['pin'])) {
            $user->forceFill(['pin_hash' => Hash::make($data['pin'])])->save();
        }

        return response()->json(self::signedIn($user, 'parent-device'), 201);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('email', $data['email'])->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            // Deliberately identical whether or not the address exists.
            throw ValidationException::withMessages([
                'email' => ['These credentials do not match our records.'],
            ]);
        }

        // The password turns a PIN locked by wrong tries back on (rule 6).
        $user->clearPinAttempts();

        return response()->json(self::signedIn($user, 'parent-device'));
    }

    /**
     * POST /parent/pin-login (PA-2): a parent's 4-digit PIN, on a phone where
     * they signed in with their password before, which the pin ticket from
     * that sign-in proves. The fifth wrong PIN turns the PIN off until the
     * next email-and-password sign-in.
     *
     * A wrong household code, a parent from another household and a wrong
     * PIN get the same answer, so nothing here confirms who has an account.
     */
    public function pinLogin(Request $request): JsonResponse
    {
        $data = $request->validate([
            'household_code' => ['required', 'string', 'size:6'],
            'parent_id' => ['required', 'integer'],
            'pin' => ['required', 'digits:4'],
            'pin_ticket' => ['required', 'string', 'max:100'],
        ]);

        // One at a time per parent, so tries made together cannot slip past
        // the fifth.
        return DB::transaction(function () use ($data) {
            $user = User::where('household_code', strtoupper($data['household_code']))
                ->whereKey($data['parent_id'])
                ->lockForUpdate()
                ->first();

            if (! $user) {
                return response()->json(['message' => 'That PIN is not right.'], 422);
            }

            // Before the PIN is looked at, so a phone that never saw the
            // password cannot guess, or use up the parent's tries.
            if (! $user->pinTicketMatches($data['pin_ticket'])) {
                return response()->json([
                    'message' => 'Sign in with your email and password on this phone first.',
                ], 423);
            }

            if (! $user->hasPin()) {
                return response()->json([
                    'message' => 'You have no sign-in PIN. Sign in with your email and password.',
                ], 423);
            }

            if (! $user->pinUsable()) {
                return response()->json([
                    'message' => 'Too many tries. Sign in with your email and password.',
                ], 423);
            }

            if (! Hash::check($data['pin'], $user->pin_hash)) {
                $left = $user->registerFailedPin();

                return $left === 0
                    ? response()->json(['message' => 'Too many tries. Sign in with your email and password.'], 423)
                    : response()->json([
                        'message' => $left === 1
                            ? 'That PIN is not right. 1 try left.'
                            : "That PIN is not right. {$left} tries left.",
                        'tries_left' => $left,
                    ], 422);
            }

            $user->clearPinAttempts();

            return response()->json(self::signedIn($user, 'parent-pin'));
        });
    }

    /**
     * Works for either kind of token, so a client can ask "who am I?"
     * without knowing which shell it is in.
     */
    public function me(Request $request): JsonResponse
    {
        $identity = $request->user();

        if ($identity instanceof User) {
            return response()->json([
                'type' => 'parent',
                'parent' => self::parentPayload($identity),
            ]);
        }

        return response()->json([
            'type' => 'child',
            'child' => [
                'id' => $identity->id,
                'name' => $identity->name,
                'avatar' => $identity->avatar,
                'age' => $identity->age(),
            ],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Signed out.']);
    }

    public static function parentPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'household_code' => $user->household_code,
            'avatar' => $user->avatar,
            'timezone' => $user->timezone,
            'has_pin' => $user->hasPin(),
        ];
    }

    /**
     * A parent token, named for how it was earned so the token table shows
     * which sign-ins used a PIN, and the ticket that lets this phone use the
     * PIN next time.
     *
     * @return array{token: string, parent: array, pin_ticket: string}
     */
    private static function signedIn(User $user, string $how): array
    {
        return [
            'token' => $user->createToken($how, ['parent'])->plainTextToken,
            'parent' => self::parentPayload($user),
            'pin_ticket' => $user->pinTicket(),
        ];
    }
}
