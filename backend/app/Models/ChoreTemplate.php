<?php

namespace App\Models;

use App\Domain\Progress\Difficulty;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ChoreTemplate extends Model
{
    use HasFactory;

    /** The movement model checks the chore during the quest session. */
    public const MODE_LSTM = 'lstm';

    /** Only the parent checks it, from the Before and After photos. */
    public const MODE_MANUAL = 'manual';

    protected $fillable = [
        'key', 'name', 'description', 'icon', 'category', 'location',
        'min_age', 'max_age', 'default_points', 'difficulty',
        'has_visible_end_state', 'verification_class',
        'verification_mode', 'model_class', 'min_active_seconds',
        'is_custom', 'owner_user_id', 'retired_at',
    ];

    protected function casts(): array
    {
        return [
            'has_visible_end_state' => 'boolean',
            'min_age' => 'integer',
            'max_age' => 'integer',
            'default_points' => 'integer',
            'difficulty' => Difficulty::class,
            'model_class' => 'integer',
            'min_active_seconds' => 'integer',
            'is_custom' => 'boolean',
            'retired_at' => 'datetime',
        ];
    }

    public function scopeForAge(Builder $query, int $age): Builder
    {
        return $query->where('min_age', '<=', $age)->where('max_age', '>=', $age);
    }

    /** Chores still in the catalogue: retired ones keep their history only. */
    public function scopeOffered(Builder $query): Builder
    {
        return $query->whereNull('retired_at');
    }

    /**
     * What one parent may see and assign: the shared catalogue and their own
     * custom chores, never another parent's.
     */
    public function scopeVisibleTo(Builder $query, User $parent): Builder
    {
        return $query->where(fn (Builder $q) => $q
            ->where('is_custom', false)
            ->orWhere('owner_user_id', $parent->id));
    }

    public function isRetired(): bool
    {
        return $this->retired_at !== null;
    }

    /** Whether the movement model checks this chore in a quest session. */
    public function isMotionChecked(): bool
    {
        return $this->verification_mode === self::MODE_LSTM && $this->model_class !== null;
    }

    public function suitsAge(int $age): bool
    {
        return $age >= $this->min_age && $age <= $this->max_age;
    }

    /**
     * Whether the photo checker may judge this chore at all. Both must hold:
     *
     * - has_visible_end_state: one photograph can show the chore finished.
     *   This is the manuscript's own scoping flag (Limitation 2); a chore
     *   without it, such as reading for ten minutes, always goes to a
     *   parent, whatever a model says, now or once the real one (C4) runs.
     * - verification_class: a trained class exists for it.
     *
     * Everything else reaches the parent for review.
     */
    public function isModelVerifiable(): bool
    {
        return $this->has_visible_end_state && $this->verification_class !== null;
    }
}
