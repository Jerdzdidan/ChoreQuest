<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Carbon;

/**
 * One 6-digit code sent to reset a forgotten password (PA-3). Only its hash
 * is kept. It lasts 15 minutes, allows 5 tries, and works once.
 *
 * @property string $email
 * @property string $code_hash
 * @property Carbon $expires_at
 * @property int $attempts
 * @property Carbon|null $used_at
 */
class PasswordResetCode extends Model
{
    public const LIFETIME_MINUTES = 15;

    public const MAX_ATTEMPTS = 5;

    /** The shortest wait before another code is sent to the same email. */
    public const RESEND_SECONDS = 60;

    protected $fillable = ['email', 'code_hash', 'expires_at'];

    protected $hidden = ['code_hash'];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
            'used_at' => 'datetime',
            'attempts' => 'integer',
        ];
    }

    /** Not used, not run out, and tries left. */
    public function isLive(Carbon $now): bool
    {
        return $this->used_at === null
            && $this->expires_at->greaterThan($now)
            && $this->attempts < self::MAX_ATTEMPTS;
    }
}
