<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One badge a child has earned. Written by BadgeService, never by a request,
 * and never read when screen time is worked out.
 */
class BadgeEarned extends Model
{
    protected $table = 'badges_earned';

    public $timestamps = false;

    protected $fillable = [
        'child_id',
        'badge_key',
        'earned_at',
    ];

    protected function casts(): array
    {
        return [
            'earned_at' => 'datetime',
        ];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }
}
