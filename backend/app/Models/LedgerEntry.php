<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Append-only. There is intentionally no update path and no updated_at column:
 * a mistake is corrected by appending a compensating entry, never by editing
 * or removing history.
 */
class LedgerEntry extends Model
{
    use HasFactory;

    public const EARNED = 'earned';
    public const CONSUMED = 'consumed';
    public const REVERSAL = 'reversal';
    public const ADJUSTMENT = 'adjustment';

    public const UPDATED_AT = null;

    protected $fillable = [
        'child_id', 'submission_id', 'entry_type', 'minutes',
        'points', 'minutes_gross', 'minutes_forfeited', 'for_date', 'note',
    ];

    protected function casts(): array
    {
        return [
            'for_date' => 'date',
            'created_at' => 'datetime',
            'minutes' => 'integer',
        ];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    public function submission(): BelongsTo
    {
        return $this->belongsTo(Submission::class);
    }
}
