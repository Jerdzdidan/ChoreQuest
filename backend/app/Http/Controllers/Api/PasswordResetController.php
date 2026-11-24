<?php

namespace App\Http\Controllers\Api;

use App\Domain\Auth\ResetCodes;
use App\Http\Controllers\Controller;
use App\Mail\ResetCodeMail;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Validation\ValidationException;
use Throwable;

/**
 * A forgotten password, reset with a 6-digit code sent by email (PA-3).
 *
 * Every answer is the same whether or not the email has an account, so
 * nobody can use these routes to find out who uses ChoreQuest.
 */
class PasswordResetController extends Controller
{
    public const SENT = 'If that email has an account, we sent a code.';

    public const WRONG_CODE = "That code isn't right, or it has run out. Check the email, or send a new code.";

    /** POST /password/forgot */
    public function forgot(Request $request): JsonResponse
    {
        $data = $request->validate(['email' => ['required', 'email', 'max:255']]);

        $user = User::where('email', $data['email'])->first();
        $code = $user ? ResetCodes::issue($user, now()) : null;
        if ($user && $code !== null) {
            try {
                Mail::to($user->email)->send(new ResetCodeMail($code));
            } catch (Throwable $e) {
                // Logged for the team; the answer stays the same, and the
                // phone offers "Send a new code" after a minute.
                report($e);
            }
        }

        return response()->json(['message' => self::SENT]);
    }

    /** POST /password/verify-code: checks the code before a new password is chosen. */
    public function verifyCode(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'code' => ['required', 'digits:6'],
        ]);

        if (! ResetCodes::check($data['email'], $data['code'], now())) {
            throw ValidationException::withMessages(['code' => [self::WRONG_CODE]]);
        }

        return response()->json(['message' => 'That code is right. Choose a new password.']);
    }

    /**
     * POST /password/reset: the code again with the new password. Signs the
     * parent out on every phone and turns a PIN locked by wrong tries back
     * on; every phone needs the new password before its PIN works again.
     */
    public function reset(Request $request): JsonResponse
    {
        // The code first, so a right code with a too-short password is not
        // spent, and a wrong one is counted before anything else is said.
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'code' => ['required', 'digits:6'],
        ]);
        $password = $request->validate(['password' => ['required', 'string', 'min:8', 'confirmed']])['password'];

        // A wrong code returns false rather than throwing, so the try it
        // used is saved instead of rolled back with the transaction.
        $changed = DB::transaction(function () use ($data, $password) {
            $user = ResetCodes::check($data['email'], $data['code'], now(), use: true);
            if (! $user) {
                return false;
            }

            $user->forceFill(['password' => $password])->save();
            $user->tokens()->delete();
            $user->clearPinAttempts();

            return true;
        });

        if (! $changed) {
            throw ValidationException::withMessages(['code' => [self::WRONG_CODE]]);
        }

        return response()->json(['message' => 'Your password is changed. Sign in with your new password.']);
    }
}
