<?php

namespace App\Http\Controllers\Api;

use App\Domain\Model\ModelConfig;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;

/**
 * GET /model-config (BE-6), for any signed-in phone: the model's thresholds,
 * evidence bands and longest ring. The app keeps the last copy and fetches
 * again at every open, using the new numbers whenever the version changes.
 */
class ModelConfigController extends Controller
{
    public function show(): JsonResponse
    {
        return response()->json(ModelConfig::forPhones());
    }
}
