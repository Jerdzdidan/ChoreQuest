<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Support\Carbon;
use Laravel\Sanctum\HasApiTokens;

/**
 * A child-user profile. Signs in with a PIN inside its parent's household and
 * receives a Sanctum token carrying only the `child` ability.
 */
class Child extends Model
{
    use HasApiTokens, HasFactory;

    protected $fillable = [
        'user_id',
        'name',
        'avatar',
        'birthdate',
        'pin_hash',
    ];

    protected $hidden = [
        'pin_hash',
    ];

    protected function casts(): array
    {
        return [
            'birthdate' => 'date',
            'locked_until' => 'datetime',
            'pin_hash' => 'hashed',
        ];
    }

    public function parent(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function allocationRule(): HasOne
    {
        return $this->hasOne(AllocationRule::class);
    }

    public function assignments(): HasMany
    {
        return $this->hasMany(Assignment::class);
    }

    public function submissions(): HasMany
    {
        return $this->hasMany(Submission::class);
    }

    /**
     * Every child has a rule. One is created with defaults on first access so
     * no code path downstream has to cope with its absence.
     */
    public function rule(): AllocationRule
    {
        return $this->allocationRule()->firstOrCreate([]);
    }

    /**
     * Drives the age-graded chore catalogue in slice 1.2.
     */
    public function age(): int
    {
        return $this->birthdate->age;
    }

    public function isLocked(): bool
    {
        return $this->locked_until !== null && $this->locked_until->isFuture();
    }

    public function registerFailedPin(): void
    {
        $this->increment('failed_pin_attempts');

        if ($this->failed_pin_attempts >= self::MAX_PIN_ATTEMPTS) {
            $this->forceFill([
                'locked_until' => Carbon::now()->addMinutes(self::LOCKOUT_MINUTES),
                'failed_pin_attempts' => 0,
            ])->save();
        }
    }

    public function clearPinAttempts(): void
    {
        if ($this->failed_pin_attempts !== 0 || $this->locked_until !== null) {
            $this->forceFill([
                'failed_pin_attempts' => 0,
                'locked_until' => null,
            ])->save();
        }
    }

    public const MAX_PIN_ATTEMPTS = 4;
    public const LOCKOUT_MINUTES = 15;
}
