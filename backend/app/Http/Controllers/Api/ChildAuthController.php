<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

/**
 * Child sign-in: pick your face inside the household, then type four digits.
 *
 * A four-year-old cannot manage an email and password, so the household code
 * pairs the device once and the PIN identifies the child from then on.
 */
class ChildAuthController extends Controller
{
    /**
     * The avatar picker. Returns first names and avatars only — never a
     * birthdate, never a lock state, nothing that would reward guessing codes.
     */
    public function roster(string $householdCode): JsonResponse
    {
        $parent = User::where('household_code', strtoupper($householdCode))->first();

        if (! $parent) {
            return response()->json(['message' => 'That household code was not recognised.'], 404);
        }

        return response()->json([
            'household' => $parent->name,
            'children' => $parent->children()->orderBy('name')->get()
                ->map(fn (Child $c) => [
                    'id' => $c->id,
                    'name' => $c->name,
                    'avatar' => $c->avatar,
                ])->all(),
        ]);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'household_code' => ['required', 'string', 'size:6'],
            'child_id' => ['required', 'integer'],
            'pin' => ['required', 'digits:4'],
        ]);

        $parent = User::where('household_code', strtoupper($data['household_code']))->first();

        $child = $parent
            ? $parent->children()->find($data['child_id'])
            : null;

        // Refuse a locked profile before the PIN is examined at all, so a
        // lockout cannot be worn down by continued guessing.
        if ($child && $child->isLocked()) {
            return response()->json([
                'message' => 'Too many tries. Ask a grown-up to help you in a little while.',
                'locked_until' => $child->locked_until->toIso8601String(),
            ], 423);
        }

        // One response for a bad code, a child in another household, and a
        // wrong PIN. Distinguishing them would confirm that a profile exists.
        if (! $child || ! Hash::check($data['pin'], $child->pin_hash)) {
            if ($child) {
                $child->registerFailedPin();
            }

            return response()->json(['message' => 'That PIN is not right.'], 422);
        }

        $child->clearPinAttempts();

        return response()->json([
            'token' => $child->createToken('child-device', ['child'])->plainTextToken,
            'child' => [
                'id' => $child->id,
                'name' => $child->name,
                'avatar' => $child->avatar,
                'age' => $child->age(),
            ],
        ]);
    }
}
