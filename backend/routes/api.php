<?php

use App\Http\Controllers\Api\AllocationRuleController;
use App\Http\Controllers\Api\AssignmentController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ChildAuthController;
use App\Http\Controllers\Api\ChildController;
use App\Http\Controllers\Api\ChoreTemplateController;
use App\Http\Controllers\Api\LedgerController;
use App\Http\Controllers\Api\MyAvatarController;
use App\Http\Controllers\Api\ProgressController;
use App\Http\Controllers\Api\ReviewController;
use App\Http\Controllers\Api\SubmissionController;
use Illuminate\Support\Facades\Route;

Route::get('/health', fn () => response()->json([
    'service' => 'ChoreQuest API',
    'status' => 'ok',
    'time' => now()->toIso8601String(),
]));

/*
|--------------------------------------------------------------------------
| Public
|--------------------------------------------------------------------------
*/

Route::post('/register', [AuthController::class, 'register'])->middleware('throttle:6,1');
Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:6,1');

Route::get('/households/{householdCode}/children', [ChildAuthController::class, 'roster'])
    ->middleware('throttle:20,1');
Route::post('/child/login', [ChildAuthController::class, 'login'])
    ->middleware('throttle:10,1');

/*
|--------------------------------------------------------------------------
| Either identity
|--------------------------------------------------------------------------
*/

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::post('/logout', [AuthController::class, 'logout']);
});

/*
|--------------------------------------------------------------------------
| Parent only
|--------------------------------------------------------------------------
|
| `abilities:parent` is what stops a child-user from reaching the settings
| that govern their own rewards. A child token is rejected here with 403
| before any controller runs.
|
*/

Route::middleware(['auth:sanctum', 'abilities:parent'])->group(function () {
    Route::apiResource('children', ChildController::class);

    // The age-graded catalogue. ?child_id= filters it to that child's band.
    Route::get('/chores', [ChoreTemplateController::class, 'index']);

    // Assignments: which chores this child has, for how many points, when.
    Route::get('/assignments', [AssignmentController::class, 'index']);
    Route::post('/assignments', [AssignmentController::class, 'store']);
    Route::patch('/assignments/{assignment}', [AssignmentController::class, 'update']);
    Route::delete('/assignments/{assignment}', [AssignmentController::class, 'destroy']);

    // Exchange rate, both caps, and both confidence thresholds.
    Route::get('/children/{child}/rule', [AllocationRuleController::class, 'show']);
    Route::patch('/children/{child}/rule', [AllocationRuleController::class, 'update']);

    // Review queue. ?scope=all includes submissions the model decided on its
    // own, so a parent can audit and overturn those too.
    Route::get('/reviews', [ReviewController::class, 'index']);
    Route::post('/submissions/{submission}/decide', [ReviewController::class, 'decide']);
    Route::get('/submissions/{submission}/photo', [ReviewController::class, 'photo']);

    // Screen-time report and running ledger for one child.
    Route::get('/children/{child}/report', [LedgerController::class, 'report']);
});

/*
|--------------------------------------------------------------------------
| Child only
|--------------------------------------------------------------------------
*/

Route::middleware(['auth:sanctum', 'abilities:child'])->group(function () {
    // Today's chores for the signed-in child.
    Route::get('/my/chores', [AssignmentController::class, 'today']);

    Route::post('/submissions', [SubmissionController::class, 'store']);
    Route::get('/my/submissions', [SubmissionController::class, 'mine']);
    Route::get('/my/balance', [LedgerController::class, 'balance']);
    Route::post('/my/consume', [LedgerController::class, 'consume']);

    // XP and the rest of the game layer, derived from approvals.
    Route::get('/my/progress', [ProgressController::class, 'mine']);

    // A child choosing their own animal from those their level unlocks.
    Route::patch('/my/avatar', [MyAvatarController::class, 'update']);
});
