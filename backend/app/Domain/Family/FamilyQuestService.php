<?php

namespace App\Domain\Family;

use App\Models\FamilyQuest;
use Illuminate\Support\Carbon;

/**
 * What a family quest has come to so far: how many approved quests count
 * towards it, and which children helped.
 *
 * Progress is never stored. It is the contributions, which are approved
 * photos, counted afresh on every read, so it can never disagree with the
 * submissions behind it.
 */
class FamilyQuestService
{
    /**
     * @return array{done: int, target: int, reached: bool, helpers: list<array{child_id: int, quests: int}>}
     */
    public function progress(FamilyQuest $quest): array
    {
        $helpers = $quest->contributions()
            ->selectRaw('child_id, COUNT(*) AS quests')
            ->groupBy('child_id')
            ->orderBy('child_id')
            ->get()
            ->map(fn ($row) => ['child_id' => (int) $row->child_id, 'quests' => (int) $row->quests])
            ->all();

        $done = array_sum(array_column($helpers, 'quests'));

        return [
            'done' => $done,
            'target' => $quest->target_count,
            'reached' => $done >= $quest->target_count,
            'helpers' => $helpers,
        ];
    }

    /**
     * Where a quest stands against a household's day: not yet begun, running,
     * or over. A quest that reached its target reads as done whatever the
     * date.
     */
    public function state(FamilyQuest $quest, Carbon $today, bool $reached): string
    {
        if ($reached) {
            return 'done';
        }
        if ($quest->starts_at->toDateString() > $today->toDateString()) {
            return 'upcoming';
        }
        if ($quest->ends_at->toDateString() < $today->toDateString()) {
            return 'missed';
        }

        return 'running';
    }
}
