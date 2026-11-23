<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * One camera a child's phone reported (BE-8). See the migration for what
 * each column means.
 */
class DeviceCamera extends Model
{
    public const KIND_PHONE = 'phone';

    public const KIND_EXTERNAL = 'external';

    public const KIND_NETWORK = 'network';

    public const KINDS = [self::KIND_PHONE, self::KIND_EXTERNAL, self::KIND_NETWORK];

    /** How long a camera counts as connected after the phone last said so. */
    public const FRESH_MINUTES = 10;

    protected $fillable = ['child_id', 'device_key', 'camera_key', 'kind', 'label', 'connected', 'last_seen_at'];

    protected function casts(): array
    {
        return [
            'connected' => 'boolean',
            'last_seen_at' => 'datetime',
        ];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    /** Cameras that are not the phone's own: USB and network ones. */
    public function scopeThirdParty(Builder $query): Builder
    {
        return $query->whereIn('kind', [self::KIND_EXTERNAL, self::KIND_NETWORK]);
    }

    /**
     * Connected as of [now]: the phone said so, and said it within the last
     * ten minutes. A phone that has gone quiet takes its cameras with it.
     */
    public function scopeConnectedAt(Builder $query, Carbon $now): Builder
    {
        return $query->where('connected', true)
            ->where('last_seen_at', '>=', $now->copy()->subMinutes(self::FRESH_MINUTES));
    }
}
