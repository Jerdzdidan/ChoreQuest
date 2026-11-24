<?php

namespace App\Models;

use App\Domain\Auth\PinTicket;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Laravel\Sanctum\HasApiTokens;

/**
 * A parent-user. The only account holder in ChoreQuest; children are profiles
 * belonging to one of these, never accounts of their own.
 */
class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    /**
     * Defaults the database also applies, set here as well so a freshly
     * created account answers with them before it is read back.
     */
    protected $attributes = [
        'avatar' => 'owl',
        'timezone' => self::DEFAULT_TIMEZONE,
    ];

    protected $fillable = [
        'name',
        'avatar',
        'email',
        'password',
        'household_code',
        'timezone',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'pin_hash',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'notifications_seen_at' => 'datetime',
            'pin_locked_at' => 'datetime',
        ];
    }

    /**
     * The household's timezone. Days (a quest's date, streaks, the daily and
     * weekly limits) are counted in it.
     */
    public const DEFAULT_TIMEZONE = 'Asia/Manila';

    /**
     * The time now where this household lives.
     */
    public function localNow(): Carbon
    {
        return Carbon::now($this->timezone ?: self::DEFAULT_TIMEZONE);
    }

    /**
     * Wrong PINs before the PIN turns off (rule 6). Unlike a child's, it
     * stays off until the next email-and-password sign-in, not for a while.
     */
    public const MAX_PIN_ATTEMPTS = 5;

    public function hasPin(): bool
    {
        return $this->pin_hash !== null;
    }

    /**
     * What a phone keeps after an email-and-password sign-in, so the PIN
     * works there (rule 6). A new password retires it.
     */
    public function pinTicket(): string
    {
        return PinTicket::issue((string) config('app.key'), $this->id, $this->password);
    }

    public function pinTicketMatches(string $ticket): bool
    {
        return PinTicket::matches($ticket, (string) config('app.key'), $this->id, $this->password);
    }

    /** Whether the PIN can be used to sign in right now. */
    public function pinUsable(): bool
    {
        return $this->hasPin() && $this->pin_locked_at === null;
    }

    /**
     * Counts a wrong PIN, and turns the PIN off at the fifth. Returns the
     * tries left; zero means it is now off.
     */
    public function registerFailedPin(): int
    {
        $attempts = $this->pin_failed_attempts + 1;
        $this->forceFill([
            'pin_failed_attempts' => $attempts,
            'pin_locked_at' => $attempts >= self::MAX_PIN_ATTEMPTS ? Carbon::now() : null,
        ])->save();

        return max(0, self::MAX_PIN_ATTEMPTS - $attempts);
    }

    /**
     * Forgets wrong PINs and turns a locked PIN back on: after a right PIN,
     * an email-and-password sign-in, a password reset, or a new PIN.
     */
    public function clearPinAttempts(): void
    {
        if ($this->pin_failed_attempts !== 0 || $this->pin_locked_at !== null) {
            $this->forceFill(['pin_failed_attempts' => 0, 'pin_locked_at' => null])->save();
        }
    }

    public function children(): HasMany
    {
        return $this->hasMany(Child::class);
    }

    /** The quests this household works on together (F1). */
    public function familyQuests(): HasMany
    {
        return $this->hasMany(FamilyQuest::class);
    }

    /**
     * A short code the parent reads aloud once when pairing a child's device.
     * Ambiguous characters are excluded so it survives being read off a screen.
     */
    public static function generateHouseholdCode(): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

        do {
            $code = '';
            for ($i = 0; $i < 6; $i++) {
                $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
        } while (static::where('household_code', $code)->exists());

        return $code;
    }
}
