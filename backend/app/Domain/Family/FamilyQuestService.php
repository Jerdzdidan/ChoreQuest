<?php

namespace App\Domain\Family;

use App\Domain\Allocation\LedgerService;
use App\Models\Child;
use App\Models\FamilyQuest;
use App\Models\FamilyQuestContribution;
use App\Models\Submission;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

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
    public function __construct(private readonly LedgerService $ledger)
    {
    }

    /**
     * Counts an approved photo towards every quest of its household whose
     * window covers the day it was done, and pays the rewards out if that
     * brings one to its target (F3).
     *
     * Called from both places an approval happens: the checker's own at
     * intake, and a grown-up's in the review screen.
     */
    public function record(Submission $submission): void
    {
        $child = $submission->child ?? Child::find($submission->child_id);

        if (! $child || ! $submission->isApproved()) {
            return;
        }

        $day = $submission->for_date instanceof Carbon
            ? $submission->for_date->toDateString()
            : substr((string) $submission->for_date, 0, 10);

        $quests = FamilyQuest::where('user_id', $child->user_id)->runningOn($day)->get();

        foreach ($quests as $quest) {
            FamilyQuestContribution::firstOrCreate(
                ['family_quest_id' => $quest->id, 'submission_id' => $submission->id],
                ['child_id' => $child->id],
            );

            $this->payIfReached($quest, $day);
        }
    }

    /**
     * Takes a photo's contributions back after a parent overturns it, so the
     * shared progress never counts a photo the parent has taken back.
     *
     * A reward already paid stays paid, like every other minute a child has
     * been told they earned.
     */
    public function withdraw(Submission $submission): void
    {
        FamilyQuestContribution::where('submission_id', $submission->id)->delete();
    }

    /**
     * Pays every child who helped, once, when a quest reaches its target.
     *
     * Each child's share hangs off one of their own approved photos: the
     * latest they contributed. The quest is locked while this runs and
     * rewarded_at is set inside the same transaction, so two approvals
     * landing together cannot pay twice.
     */
    private function payIfReached(FamilyQuest $quest, string $day): void
    {
        DB::transaction(function () use ($quest, $day) {
            $locked = FamilyQuest::whereKey($quest->id)->lockForUpdate()->first();

            if (! $locked || $locked->isRewarded()) {
                return;
            }

            $contributions = $locked->contributions()->orderBy('id')->get();

            if ($contributions->count() < $locked->target_count) {
                return;
            }

            foreach ($contributions->groupBy('child_id') as $childId => $theirs) {
                $child = Child::find($childId);
                $latest = Submission::find($theirs->last()->submission_id);

                if ($child && $latest) {
                    $this->ledger->creditFamilyReward($child, $locked, $latest, Carbon::parse($day));
                }
            }

            $locked->forceFill(['rewarded_at' => now()])->save();
        });
    }

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
