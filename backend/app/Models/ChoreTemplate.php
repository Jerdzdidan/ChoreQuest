<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ChoreTemplate extends Model
{
    use HasFactory;

    protected $fillable = [
        'name', 'description', 'icon', 'category',
        'min_age', 'max_age', 'default_points',
        'has_visible_end_state', 'verification_class',
    ];

    protected function casts(): array
    {
        return [
            'has_visible_end_state' => 'boolean',
            'min_age' => 'integer',
            'max_age' => 'integer',
            'default_points' => 'integer',
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
     * True only when a trained class exists for this chore. Everything else
     * reaches the parent regardless of how photographable it is.
     */
    public function isModelVerifiable(): bool
    {
        return $this->verification_class !== null;
    }
}
