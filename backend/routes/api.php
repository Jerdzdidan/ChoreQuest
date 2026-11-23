<?php

use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\AlarmController;
use App\Http\Controllers\Api\AllocationRuleController;
use App\Http\Controllers\Api\AssignmentController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ChildAuthController;
use App\Http\Controllers\Api\ChildController;
use App\Http\Controllers\Api\ChoreTemplateController;
use App\Http\Controllers\Api\DeviceCameraController;
use App\Http\Controllers\Api\DeviceStatusController;
use App\Http\Controllers\Api\FamilyQuestController;
use App\Http\Controllers\Api\LedgerController;
use App\Http\Controllers\Api\ModelConfigController;
use App\Http\Controllers\Api\MyScheduleController;
use App\Http\Controllers\Api\MyAvatarController;
use App\Http\Controllers\Api\MyCosmeticsController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\ProgressController;
use App\Http\Controllers\Api\ReviewController;
use App\Http\Controllers\Api\SessionController;
use App\Http\Controllers\Api\SubmissionController;
use App\Http\Controllers\Api\TimezoneController;
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
    // The phone's timezone, sent at sign-in; days are counted in it.
    Route::patch('/me/timezone', [TimezoneController::class, 'update']);

    // The movement model's thresholds, tunable without a rebuild (BE-6).
    Route::get('/model-config', [ModelConfigController::class, 'show']);
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
    // The parent's own account: name, email, picture, password.
    Route::patch('/me', [AccountController::class, 'update']);

    Route::apiResource('children', ChildController::class);

    // The age-graded catalogue. ?child_id= filters it to that child's band.
    Route::get('/chores', [ChoreTemplateController::class, 'index']);
    // A chore the parent makes up (PS-2): seen only by them, checked only
    // by them.
    Route::post('/chores/custom', [ChoreTemplateController::class, 'storeCustom']);

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

    // One child's figures for the Activity tab: completion, streak, XP, week.
    Route::get('/children/{child}/activity', [ProgressController::class, 'activity']);

    // The third-party cameras connected to a child's phone right now (BE-8).
    Route::get('/children/{child}/cameras', [DeviceCameraController::class, 'index']);

    // Quests the whole household works on together (F1, F2).
    Route::get('/family-quests', [FamilyQuestController::class, 'index']);
    Route::post('/family-quests', [FamilyQuestController::class, 'store']);
    Route::delete('/family-quests/{familyQuest}', [FamilyQuestController::class, 'destroy']);

    // One notification per photo sent, from the submissions themselves.
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::post('/notifications/seen', [NotificationController::class, 'seen']);
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
    // A finished live quest session: Before, After and the evidence (BE-2).
    // Never credited here; only a parent's approval is.
    Route::post('/quest-sessions', [SessionController::class, 'store']);
    Route::get('/my/submissions', [SubmissionController::class, 'mine']);
    Route::get('/my/balance', [LedgerController::class, 'balance']);
    Route::post('/my/consume', [LedgerController::class, 'consume']);

    // XP and the rest of the game layer, derived from approvals.
    Route::get('/my/progress', [ProgressController::class, 'mine']);

    // The household's shared quests, as a child sees them (F3).
    Route::get('/my/family-quests', [FamilyQuestController::class, 'mine']);

    // A child choosing their own animal from those their level unlocks.
    Route::patch('/my/avatar', [MyAvatarController::class, 'update']);

    // Cosmetics: what a child has unlocked. The app reports what its level
    // unlocks; the server records each item once.
    Route::get('/my/cosmetics', [MyCosmeticsController::class, 'index']);
    Route::post('/my/cosmetics', [MyCosmeticsController::class, 'store']);
    // Put on one item the child owns: one per category at a time.
    Route::patch('/my/cosmetics', [MyCosmeticsController::class, 'update']);

    // The cameras this phone can see, replacing what it reported before (BE-8).
    Route::post('/my/cameras', [DeviceCameraController::class, 'store']);

    // Everything the phone needs to arm its alarms offline (BE-7).
    Route::get('/my/schedule', [MyScheduleController::class, 'show']);

    // Whether this phone is ready to ring (BE-9).
    Route::post('/my/device-status', [DeviceStatusController::class, 'store']);

    // An alarm that timed out, or a camera that was missing (DV-7, DV-12).
    Route::post('/my/alarm-events', [AlarmController::class, 'report']);

    // The grown-up stop: the parent's password on the child's phone (BE-10).
    // Rate-limited, as a password check must be.
    Route::post('/alarm/override', [AlarmController::class, 'override'])->middleware('throttle:alarm-override');
});
