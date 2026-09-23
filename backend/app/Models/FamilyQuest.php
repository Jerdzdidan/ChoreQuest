<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * A quest the whole household works on together (F1): a number of approved
 * quests to reach between them by a date, and the screen time each child who
 * helped receives when they do.
 *
 * The household is the parent, as everywhere else in this schema. Progress is
 * the contributions, which are approved photos; nothing about a family quest
 * writes screen time on its own.
 */
class FamilyQuest extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'title',
        'target_count',
        'reward_minutes_each',
        'starts_at',
        'ends_at',
    ];

    protected function casts(): array
    {
        return [
            'starts_at' => 'date',
            'ends_at' => 'date',
            'rewarded_at' => 'datetime',
            'target_count' => 'integer',
            'reward_minutes_each' => 'integer',
        ];
    }

    public function household(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function contributions(): HasMany
    {
        return $this->hasMany(FamilyQuestContribution::class);
    }

    /** Quests whose window covers [$date], in the household's own day. */
    public function scopeRunningOn(Builder $query, Carbon|string $date): Builder
    {
        $day = $date instanceof Carbon ? $date->toDateString() : $date;

        return $query->whereDate('starts_at', '<=', $day)->whereDate('ends_at', '>=', $day);
    }

    public function covers(Carbon|string $date): bool
    {
        $day = $date instanceof Carbon ? $date->toDateString() : substr((string) $date, 0, 10);

        return $this->starts_at->toDateString() <= $day && $this->ends_at->toDateString() >= $day;
    }

    /** Whether the minutes have gone out already. */
    public function isRewarded(): bool
    {
        return $this->rewarded_at !== null;
    }
}
