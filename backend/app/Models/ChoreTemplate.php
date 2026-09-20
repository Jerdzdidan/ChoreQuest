<?php

namespace App\Models;

use App\Domain\Progress\Difficulty;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ChoreTemplate extends Model
{
    use HasFactory;

    protected $fillable = [
        'name', 'description', 'icon', 'category',
        'min_age', 'max_age', 'default_points', 'difficulty',
        'has_visible_end_state', 'verification_class',
    ];

    protected function casts(): array
    {
        return [
            'has_visible_end_state' => 'boolean',
            'min_age' => 'integer',
            'max_age' => 'integer',
            'default_points' => 'integer',
            'difficulty' => Difficulty::class,
        ];
    }

    public function scopeForAge(Builder $query, int $age): Builder
    {
        return $query->where('min_age', '<=', $age)->where('max_age', '>=', $age);
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
