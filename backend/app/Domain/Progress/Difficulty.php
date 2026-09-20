<?php

namespace App\Domain\Progress;

/**
 * How hard a chore is, and the XP an approved quest of that difficulty earns.
 *
 * The only place these numbers live on the server. The app keeps a matching
 * copy in lib/shared/difficulty_xp.dart for showing a quest's XP before it is
 * earned; the server's is the one that counts.
 */
enum Difficulty: string
{
    case Easy = 'easy';
    case Medium = 'medium';
    case Hard = 'hard';

    public function xp(): int
    {
        return match ($this) {
            self::Easy => 5,
            self::Medium => 10,
            self::Hard => 20,
        };
    }

    /**
     * The tier a chore's default points suggest, for a catalogue entry that
     * does not name one: 3 or fewer is easy, 4 or 5 medium, 6 or more hard.
     */
    public static function fromPoints(int $points): self
    {
        return match (true) {
            $points <= 3 => self::Easy,
            $points <= 5 => self::Medium,
            default => self::Hard,
        };
    }
}
