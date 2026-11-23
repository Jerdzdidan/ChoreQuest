<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Whether a child's phone is ready to ring (BE-9). See the migration.
 */
class DeviceStatus extends Model
{
    protected $fillable = ['child_id', 'checklist_passed', 'checks', 'last_sync_at', 'app_version', 'reported_at'];

    protected function casts(): array
    {
        return [
            'checklist_passed' => 'boolean',
            'checks' => 'array',
            'last_sync_at' => 'datetime',
            'reported_at' => 'datetime',
        ];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    /**
     * What the parent's Board shows for a child: ready, needs_setup, or
     * unknown when the phone has never reported.
     *
     * @return array{state: string, checks: array<string, bool>, last_sync_at: ?string, reported_at: ?string, app_version: ?string}
     */
    public static function summaryFor(?self $status): array
    {
        if ($status === null) {
            return ['state' => 'unknown', 'checks' => [], 'last_sync_at' => null, 'reported_at' => null, 'app_version' => null];
        }

        return [
            'state' => $status->checklist_passed ? 'ready' : 'needs_setup',
            'checks' => $status->checks ?? [],
            'last_sync_at' => $status->last_sync_at?->toIso8601String(),
            'reported_at' => $status->reported_at?->toIso8601String(),
            'app_version' => $status->app_version,
        ];
    }
}
