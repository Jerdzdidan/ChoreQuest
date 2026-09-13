<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * Parent-only management of child profiles. Every route here is reached with a
 * `parent` ability token; a child token is refused before this class is hit.
 */
class ChildController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $children = $request->user()->children()->orderBy('name')->get();

        return response()->json([
            'children' => $children->map(fn (Child $c) => $this->payload($c))->all(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'avatar' => ['required', 'string', 'max:32'],
            'birthdate' => ['required', 'date', 'before:today'],
            'pin' => ['required', 'digits:4'],
        ]);

        $child = $request->user()->children()->create([
            'name' => $data['name'],
            'avatar' => $data['avatar'],
            'birthdate' => $data['birthdate'],
            'pin_hash' => $data['pin'],
        ]);

        return response()->json(['child' => $this->payload($child)], 201);
    }

    public function show(Request $request, Child $child): JsonResponse
    {
        $this->authoriseOwnership($request, $child);

        return response()->json(['child' => $this->payload($child)]);
    }

    public function update(Request $request, Child $child): JsonResponse
    {
        $this->authoriseOwnership($request, $child);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'avatar' => ['sometimes', 'string', 'max:32'],
            'birthdate' => ['sometimes', 'date', 'before:today'],
            'pin' => ['sometimes', 'digits:4'],
        ]);

        if (isset($data['pin'])) {
            $data['pin_hash'] = $data['pin'];
            unset($data['pin']);
        }

        $child->update($data);

        // Changing the PIN is also how a parent lifts a lockout.
        if ($child->wasChanged('pin_hash')) {
            $child->clearPinAttempts();
        }

        return response()->json(['child' => $this->payload($child->fresh())]);
    }

    public function destroy(Request $request, Child $child): JsonResponse
    {
        $this->authoriseOwnership($request, $child);

        $childId = $child->id;

        $child->tokens()->delete();
        $child->delete();

        // The database cascade removes the submission rows but not the files
        // they point at. These are photographs of a child inside their home,
        // so they must not outlive the profile on disk. Removed after the rows,
        // so a failed delete can never leave rows pointing at missing files.
        Storage::disk('local')->deleteDirectory("submissions/{$childId}");

        return response()->json(['message' => 'Child profile removed.']);
    }

    /**
     * A parent may only ever touch their own household's children.
     */
    private function authoriseOwnership(Request $request, Child $child): void
    {
        abort_unless($child->user_id === $request->user()->id, 404);
    }

    private function payload(Child $child): array
    {
        return [
            'id' => $child->id,
            'name' => $child->name,
            'avatar' => $child->avatar,
            'birthdate' => $child->birthdate->toDateString(),
            'age' => $child->age(),
            'is_locked' => $child->isLocked(),
        ];
    }
}
