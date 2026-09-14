<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * A child changing their own avatar, from the animals they have unlocked.
 *
 * Which animals are unlocked is worked out in the app from the child's level,
 * because levels live there (lib/shared/leveling.dart). It is cosmetic: a
 * tampered app could wear an animal early, and nothing else depends on it.
 * What the server does guard is sign-in. Children find themselves by their
 * face on the "Who are you?" screen, so a child may not take an animal a
 * brother or sister already has.
 */
class MyAvatarController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        /** @var Child $child */
        $child = $request->user();

        $data = $request->validate([
            'avatar' => ['required', 'string', 'max:32', 'alpha_dash'],
        ]);

        $takenBySibling = Child::where('user_id', $child->user_id)
            ->whereKeyNot($child->id)
            ->where('avatar', $data['avatar'])
            ->exists();

        if ($takenBySibling) {
            throw ValidationException::withMessages([
                'avatar' => ['Your brother or sister already has this one. Pick another!'],
            ]);
        }

        $child->update(['avatar' => $data['avatar']]);

        return response()->json([
            'child' => [
                'id' => $child->id,
                'name' => $child->name,
                'avatar' => $child->avatar,
                'age' => $child->age(),
            ],
        ]);
    }
}
