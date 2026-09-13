<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AllocationRule extends Model
{
    use HasFactory;

    /**
     * Mirrors the column defaults so a rule created through firstOrCreate()
     * carries them in memory too. Without this, a newly created rule has only
     * its key and timestamps populated until it is refreshed from the
     * database, and any code reading a threshold off it sees nothing.
     */
    protected $attributes = [
        'minutes_per_point' => 5,
        'daily_cap_minutes' => 60,
        'weekly_cap_minutes' => 300,
        'confidence_high' => 0.850,
        'confidence_low' => 0.400,
    ];

    protected $fillable = [
        'child_id',
        'minutes_per_point',
        'daily_cap_minutes',
        'weekly_cap_minutes',
        'confidence_high',
        'confidence_low',
    ];

    protected function casts(): array
    {
        return [
            'minutes_per_point' => 'integer',
            'daily_cap_minutes' => 'integer',
            'weekly_cap_minutes' => 'integer',
            'confidence_high' => 'float',
            'confidence_low' => 'float',
        ];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }
}
