<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Records the household's timezone as a phone reports it.
 *
 * Either kind of token may call this: the app sends the phone's own timezone
 * when a parent or a child signs in. Both belong to the same household, so a
 * child's phone updates their parent's household too. Nothing else about the
 * account changes.
 */
class TimezoneController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            // Any IANA name PHP knows, e.g. Asia/Manila. Abbreviations like
            // "PST" are ambiguous and refused.
            'timezone' => ['required', 'string', 'max:64', 'timezone:all'],
        ]);

        $identity = $request->user();
        $household = $identity instanceof Child ? $identity->parent : $identity;

        abort_unless($household instanceof User, 404);

        $household->update(['timezone' => $data['timezone']]);

        return response()->json(['timezone' => $household->timezone]);
    }
}
