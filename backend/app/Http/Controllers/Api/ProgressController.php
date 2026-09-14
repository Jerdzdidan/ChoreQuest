<?php

namespace App\Http\Controllers\Api;

use App\Domain\Progress\ProgressService;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The child's game progress. Read-only: nothing a child or parent does here
 * changes it; it follows from approvals.
 */
class ProgressController extends Controller
{
    public function __construct(private readonly ProgressService $progress)
    {
    }

    public function mine(Request $request): JsonResponse
    {
        $child = $request->user();

        return response()->json([
            // The server's date, which submissions count against.
            'today' => now()->toDateString(),
            'xp' => $this->progress->xp($child),
        ]);
    }
}
