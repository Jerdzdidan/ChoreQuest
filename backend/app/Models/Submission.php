<?php

namespace App\Models;

use App\Domain\Verification\Decision;
use App\Domain\Verification\Routing;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Submission extends Model
{
    use HasFactory;

    protected $fillable = [
        'child_id', 'assignment_id', 'photo_path',
        'model_label', 'model_confidence', 'model_version', 'inference_ms',
        'routing', 'parent_decision', 'parent_decided_at', 'parent_user_id',
        'status', 'for_date', 'client_token',
    ];

    protected function casts(): array
    {
        return [
            'model_confidence' => 'float',
            'inference_ms' => 'integer',
            'parent_decided_at' => 'datetime',
            'for_date' => 'date',
        ];
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    public function assignment(): BelongsTo
    {
        return $this->belongsTo(Assignment::class);
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'parent_user_id');
    }

    public function scopePending(Builder $query): Builder
    {
        return $query->where('status', Decision::PENDING);
    }

    public function isApproved(): bool
    {
        return $this->status === Decision::APPROVED;
    }

    /**
     * True when a person looked at this and disagreed with the machine.
     * The pair of columns this reads is what Chapter 4's error rates are
     * computed from, which is why neither may be overwritten by the other.
     */
    public function wasOverridden(): bool
    {
        if ($this->parent_decision === null) {
            return false;
        }

        return match ($this->routing) {
            Routing::AUTO_APPROVED => $this->parent_decision === Decision::REJECTED,
            Routing::AUTO_REJECTED => $this->parent_decision === Decision::APPROVED,
            default => false,
        };
    }
}
