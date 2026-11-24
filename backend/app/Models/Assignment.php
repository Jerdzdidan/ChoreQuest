<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

class Assignment extends Model
{
    use HasFactory;

    /**
     * The places on a child's quest map. A chore with no particular place
     * is "other", which the map shows as its own group.
     */
    public const LOCATIONS = ['kitchen', 'bedroom', 'study', 'outdoor', 'other'];

    /** The child's own phone, its back camera on a strap (CAM-1). */
    public const CAMERA_PHONE = 'phone';

    /**
     * A third-party camera, before Phase 5. No quest uses one now; the name
     * stays so older submissions still read.
     */
    public const CAMERA_EXTERNAL = 'external';

    /** What a quest can be scheduled with: the phone only, since CAM-1. */
    public const CAMERA_SOURCES = [self::CAMERA_PHONE];

    public const DEFAULT_RINGTONE = 'classic';

    protected $fillable = [
        'child_id', 'chore_template_id', 'points',
        'due_time', 'recurrence', 'scheduled_date', 'is_active', 'location',
        'days_of_week', 'ringtone_key', 'camera_source', 'camera_device_id', 'alarm_enabled',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_date' => 'date',
            'is_active' => 'boolean',
            'points' => 'integer',
            'days_of_week' => 'array',
            'alarm_enabled' => 'boolean',
        ];
    }

    /**
     * Whether a daily quest with these weekdays repeats on [isoWeekday]
     * (1 Monday to 7 Sunday). No weekdays means every day.
     *
     * @param  list<int>|null  $daysOfWeek
     */
    public static function repeatsOn(?array $daysOfWeek, int $isoWeekday): bool
    {
        return $daysOfWeek === null || in_array($isoWeekday, $daysOfWeek, true);
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(ChoreTemplate::class, 'chore_template_id');
    }

    /**
     * What the child sees today: every active daily assignment that repeats
     * on this weekday (or on every day), plus any one-off scheduled for this
     * date. [date] is the household's own date (TZ3), so its weekday is the
     * household's weekday.
     */
    public function scopeDueOn(Builder $query, Carbon $date): Builder
    {
        return $query->where('is_active', true)
            ->where(function (Builder $q) use ($date) {
                $q->where(function (Builder $daily) use ($date) {
                    $daily->where('recurrence', 'daily')
                        ->where(fn (Builder $days) => $days
                            ->whereNull('days_of_week')
                            ->orWhereJsonContains('days_of_week', $date->isoWeekday()));
                })
                    ->orWhere(function (Builder $q2) use ($date) {
                        $q2->where('recurrence', 'once')
                            ->whereDate('scheduled_date', $date->toDateString());
                    });
            });
    }
}
