<?php

namespace App\Domain\Progress;

/**
 * How many of the quests a child was given over a run of days they
 * completed: the completion rate on the parent's Activity tab (ACT1).
 *
 * A pure function, like the streak calculator: the assignments, the
 * approvals and the days are passed in, and nothing is read from the clock
 * or the database, so any case can be checked by hand.
 *
 * A quest is due on a day when the child's app would have listed it that day
 * under the rules Assignment::scopeDueOn applies today: an active daily
 * assignment that already existed, or an active one-off scheduled for that
 * day. It is done when a photo sent that day for it was approved. One
 * assignment counts once a day however many photos were sent, so done can
 * never exceed due.
 *
 * Days are plain Y-m-d dates in the household's timezone, like for_date.
 */
final class CompletionRate
{
    /**
     * @param  list<array{id: int, recurrence: string, scheduled_date: ?string, created_on: string, active: bool}>  $assignments
     * @param  list<array{assignment_id: int, for_date: string}>  $approved
     * @param  list<string>  $days
     * @return array{due: int, done: int}
     */
    public function over(array $assignments, array $approved, array $days): array
    {
        $doneOn = [];
        foreach ($approved as $row) {
            $doneOn[$row['assignment_id'].'@'.$row['for_date']] = true;
        }

        $due = 0;
        $done = 0;
        foreach ($days as $day) {
            foreach ($assignments as $assignment) {
                if (! $this->dueOn($assignment, $day)) {
                    continue;
                }
                $due++;
                if (isset($doneOn[$assignment['id'].'@'.$day])) {
                    $done++;
                }
            }
        }

        return ['due' => $due, 'done' => $done];
    }

    /**
     * @param  array{id: int, recurrence: string, scheduled_date: ?string, created_on: string, active: bool}  $assignment
     */
    private function dueOn(array $assignment, string $day): bool
    {
        if (! $assignment['active']) {
            return false;
        }

        return match ($assignment['recurrence']) {
            'daily' => $assignment['created_on'] <= $day,
            'once' => $assignment['scheduled_date'] === $day,
            default => false,
        };
    }
}
