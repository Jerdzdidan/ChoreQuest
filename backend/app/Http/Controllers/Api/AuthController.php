<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Parent-user authentication. Issues tokens carrying the `parent` ability only.
 */
class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => $data['password'],
            'household_code' => User::generateHouseholdCode(),
        ]);

        return response()->json([
            'token' => $user->createToken('parent-device', ['parent'])->plainTextToken,
            'parent' => $this->parentPayload($user),
        ], 201);
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

        return response()->json([
            'token' => $user->createToken('parent-device', ['parent'])->plainTextToken,
            'parent' => $this->parentPayload($user),
        ]);
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
                'parent' => $this->parentPayload($identity),
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

    private function parentPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'household_code' => $user->household_code,
        ];
    }
}
