<?php

namespace App\Domain\Progress;

/**
 * The quests a child missed on a day (LS-12): due that day, by the rule the
 * completion rate counts with (CompletionRate::dueOn), and nothing sent for
 * that day at all, whatever became of what was sent.
 *
 * A pure function like CompletionRate: the assignments, what was sent and the
 * day are passed in. It only names quests. Nothing is taken away for a missed
 * one: not XP, not a streak already earned, not minutes.
 */
final class MissedQuests
{
    /**
     * @param  list<array{id: int, recurrence: string, scheduled_date: ?string, created_on: string, active: bool, days_of_week?: ?list<int>}>  $assignments
     * @param  list<array{assignment_id: int, for_date: string}>  $sent
     * @return list<int> the assignments missed on $day, in the order given
     */
    public function on(array $assignments, array $sent, string $day): array
    {
        $sentFor = [];
        foreach ($sent as $row) {
            if ($row['for_date'] === $day) {
                $sentFor[$row['assignment_id']] = true;
            }
        }

        $missed = [];
        foreach ($assignments as $assignment) {
            if (CompletionRate::dueOn($assignment, $day) && ! isset($sentFor[$assignment['id']])) {
                $missed[] = $assignment['id'];
            }
        }

        return $missed;
    }
}
