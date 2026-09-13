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

    protected $fillable = [
        'child_id', 'chore_template_id', 'points',
        'due_time', 'recurrence', 'scheduled_date', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_date' => 'date',
            'is_active' => 'boolean',
            'points' => 'integer',
        ];
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
     * What the child sees today: every active daily assignment, plus any
     * one-off scheduled for this date.
     */
    public function scopeDueOn(Builder $query, Carbon $date): Builder
    {
        return $query->where('is_active', true)
            ->where(function (Builder $q) use ($date) {
                $q->where('recurrence', 'daily')
                    ->orWhere(function (Builder $q2) use ($date) {
                        $q2->where('recurrence', 'once')
                            ->whereDate('scheduled_date', $date->toDateString());
                    });
            });
    }
}
