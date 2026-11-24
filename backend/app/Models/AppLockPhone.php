<?php

namespace App\Models;

use App\Domain\AppLock\PhoneHealth;
use App\Domain\AppLock\PhoneTicket;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * A phone App Lock is turned on for, and what it last reported (AL-4). See
 * the migration.
 *
 * @property int $user_id
 * @property string $device_key
 * @property string $name
 * @property string $ticket_salt
 * @property array<string, bool>|null $checks
 * @property Carbon|null $problems_since
 * @property Carbon|null $reported_at
 * @property Carbon $created_at
 */
class AppLockPhone extends Model
{
    protected $fillable = ['user_id', 'device_key', 'name', 'ticket_salt'];

    protected $hidden = ['ticket_salt'];

    protected function casts(): array
    {
        return [
            'checks' => 'array',
            'problems_since' => 'datetime',
            'reported_at' => 'datetime',
        ];
    }

    public function household(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function ticket(): string
    {
        return PhoneTicket::issue((string) config('app.key'), $this->user_id, $this->device_key, $this->ticket_salt);
    }

    public function ticketMatches(string $ticket): bool
    {
        return PhoneTicket::matches($ticket, (string) config('app.key'), $this->user_id, $this->device_key, $this->ticket_salt);
    }

    /** @return array{state: string, since: ?Carbon, missing: list<string>} */
    public function health(Carbon $now): array
    {
        return PhoneHealth::of($this->checks, $this->problems_since, $this->reported_at, $this->created_at, $now);
    }

    /** @return array<string, mixed> */
    public function toPayload(Carbon $now): array
    {
        $health = $this->health($now);

        return [
            'device_key' => $this->device_key,
            'name' => $this->name,
            'turned_on_at' => $this->created_at->toIso8601String(),
            'reported_at' => $this->reported_at?->toIso8601String(),
            'checks' => $this->checks ?? (object) [],
            'state' => $health['state'],
            'since' => $health['since']?->toIso8601String(),
            'missing' => $health['missing'],
        ];
    }
}
