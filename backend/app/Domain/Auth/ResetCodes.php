<?php

namespace App\Domain\Auth;

use App\Models\PasswordResetCode;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * The 6-digit codes that reset a forgotten password (PA-3).
 *
 * Only the newest code sent to an email counts. It lasts 15 minutes, and
 * each wrong try uses one of its 5; after the fifth it is void and a new
 * one is needed. Only a hash is kept, and the clock is passed in.
 */
final class ResetCodes
{
    /**
     * A new code for this account, or null when one went to the same email
     * under a minute ago (the phone offers "Send a new code" after 60
     * seconds, and this stops the button being used to flood an inbox).
     */
    public static function issue(User $user, Carbon $now): ?string
    {
        $latest = PasswordResetCode::where('email', $user->email)->latest('id')->first();
        if ($latest && $latest->created_at->greaterThan($now->copy()->subSeconds(PasswordResetCode::RESEND_SECONDS))) {
            return null;
        }

        $code = str_pad((string) random_int(0, 999_999), 6, '0', STR_PAD_LEFT);
        PasswordResetCode::create([
            'email' => $user->email,
            'code_hash' => Hash::make($code),
            'expires_at' => $now->copy()->addMinutes(PasswordResetCode::LIFETIME_MINUTES),
        ]);

        return $code;
    }

    /**
     * The account the code belongs to when it is right and live, else null.
     * A wrong code counts as a try. With $use, a right code is spent, so it
     * changes a password once.
     *
     * Call inside a transaction when the code is spent, so the code and the
     * new password are saved together. The row is locked, so tries made at
     * the same moment cannot slip past the fifth.
     */
    public static function check(string $email, string $code, Carbon $now, bool $use = false): ?User
    {
        return DB::transaction(function () use ($email, $code, $now, $use) {
            $row = PasswordResetCode::where('email', $email)->latest('id')->lockForUpdate()->first();
            if (! $row || ! $row->isLive($now)) {
                return null;
            }

            if (! Hash::check($code, $row->code_hash)) {
                $row->forceFill(['attempts' => $row->attempts + 1])->save();

                return null;
            }

            $user = User::where('email', $row->email)->first();
            if ($user && $use) {
                $row->forceFill(['used_at' => $now])->save();
            }

            return $user;
        });
    }
}
