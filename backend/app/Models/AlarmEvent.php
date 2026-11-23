<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Something that happened to a quest alarm that the parent hears about. See
 * the migration for the three kinds.
 */
class AlarmEvent extends Model
{
    public const OVERRIDE = 'override';

    public const TIMED_OUT = 'timed_out';

    public const CAMERA_MISSING = 'camera_missing';

    /** What the child's phone may report itself; an override goes through its own route. */
    public const REPORTABLE = [self::TIMED_OUT, self::CAMERA_MISSING];

    protected $fillable = ['child_id', 'assignment_id', 'kind'];

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    public function assignment(): BelongsTo
    {
        return $this->belongsTo(Assignment::class);
    }
}
