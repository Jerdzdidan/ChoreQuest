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
 * The parent's own account: their name, email, picture and password.
 *
 * Only what is sent changes. A new password needs the current one, so a phone
 * left unlocked cannot be used to take the account over.
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

        if (isset($data['password']) && ! Hash::check($data['current_password'] ?? '', $parent->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['That is not your current password.'],
            ]);
        }

        $parent->fill(array_intersect_key($data, array_flip(['name', 'email', 'avatar', 'password'])));
        $parent->save();

        return response()->json(['parent' => AuthController::parentPayload($parent->fresh())]);
    }
}
