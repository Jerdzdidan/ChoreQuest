<?php

namespace App\Domain\Allocation;

/**
 * The result of one allocation. Immutable, and it carries the workings rather
 * than only the answer, so the child screen can say "you earned 20, but 5 were
 * over today's limit" instead of silently showing a smaller number.
 */
final readonly class Allocation
{
    public function __construct(
        public int $points,
        public int $grossMinutes,
        public int $releasedMinutes,
        public int $forfeitedMinutes,
        public int $dailyRemainingBefore,
        public int $weeklyRemainingBefore,
        public ?string $cappedBy,
    ) {
    }

    public function wasCapped(): bool
    {
        return $this->forfeitedMinutes > 0;
    }

    public function toArray(): array
    {
        return [
            'points' => $this->points,
            'gross_minutes' => $this->grossMinutes,
            'released_minutes' => $this->releasedMinutes,
            'forfeited_minutes' => $this->forfeitedMinutes,
            'capped_by' => $this->cappedBy,
        ];
    }
}
