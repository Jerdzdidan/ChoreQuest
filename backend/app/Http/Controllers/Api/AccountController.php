<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * The parent's own account: their name, email, picture, password and
 * sign-in PIN.
 *
 * Only what is sent changes. A new password or PIN needs the current
 * password, so a phone left unlocked cannot be used to take the account over.
 */
class AccountController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        /** @var User $parent */
        $parent = $request->user();

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'email' => ['sometimes', 'email', 'max:255', Rule::unique('users', 'email')->ignore($parent->id)],
            'avatar' => ['sometimes', 'string', 'max:32', 'alpha_dash'],
            'password' => ['sometimes', 'string', 'min:8', 'confirmed'],
            // Required whenever a new password is sent, and checked here
            // rather than with the current_password rule, which reads the
            // session guard instead of this token's owner.
            'current_password' => ['required_with:password', 'string'],
        ]);

        if (isset($data['password'])) {
            self::checkPassword($parent, $data['current_password'] ?? '');
        }

        $parent->fill(array_intersect_key($data, array_flip(['name', 'email', 'avatar', 'password'])));
        $parent->save();
        $parent = $parent->fresh();

        // A new password retires every phone's pin ticket (rule 6). This
        // phone has just shown the password, so it gets a fresh one; the
        // others need the new password before their PIN works again.
        return response()->json([
            'parent' => AuthController::parentPayload($parent),
            ...(isset($data['password']) ? ['pin_ticket' => $parent->pinTicket()] : []),
        ]);
    }

    /**
     * PUT /me/pin (PA-2): sets or changes the parent's sign-in PIN, after
     * the current password. Also turns a PIN locked by wrong tries back on.
     */
    public function setPin(Request $request): JsonResponse
    {
        /** @var User $parent */
        $parent = $request->user();

        $data = $request->validate([
            'pin' => ['required', 'digits:4'],
            'current_password' => ['required', 'string'],
        ]);

        self::checkPassword($parent, $data['current_password']);

        $parent->forceFill([
            'pin_hash' => Hash::make($data['pin']),
            'pin_failed_attempts' => 0,
            'pin_locked_at' => null,
        ])->save();

        return response()->json([
            'parent' => AuthController::parentPayload($parent),
            // The password was just typed on this phone.
            'pin_ticket' => $parent->pinTicket(),
        ]);
    }

    /** DELETE /me/pin (PA-2): turns the sign-in PIN off. */
    public function removePin(Request $request): JsonResponse
    {
        /** @var User $parent */
        $parent = $request->user();

        $parent->forceFill([
            'pin_hash' => null,
            'pin_failed_attempts' => 0,
            'pin_locked_at' => null,
        ])->save();

        return response()->json(['parent' => AuthController::parentPayload($parent)]);
    }

    private static function checkPassword(User $parent, string $password): void
    {
        if (! Hash::check($password, $parent->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['That is not your current password.'],
            ]);
        }
    }
}
