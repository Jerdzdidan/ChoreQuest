<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One approved photo counted towards a family quest (F1).
 *
 * Written when a parent's approval lands inside the quest's window, and
 * removed again if that approval is overturned, so the shared progress never
 * counts a photo the parent has taken back.
 */
class FamilyQuestContribution extends Model
{
    use HasFactory;

    protected $fillable = [
        'family_quest_id',
        'child_id',
        'submission_id',
    ];

    public function quest(): BelongsTo
    {
        return $this->belongsTo(FamilyQuest::class, 'family_quest_id');
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
