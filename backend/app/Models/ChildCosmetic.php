<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One cosmetic a child has unlocked, and whether they have it on. Written by
 * CosmeticService, and never read when screen time is worked out.
 */
class ChildCosmetic extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'child_id',
        'category',
        'item_key',
        'unlocked_at',
        'equipped',
    ];

    protected function casts(): array
    {
        return [
            'unlocked_at' => 'datetime',
            'equipped' => 'boolean',
        ];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }
}
