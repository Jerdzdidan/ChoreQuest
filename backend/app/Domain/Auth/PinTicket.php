<?php

namespace App\Domain\Auth;

/**
 * Proof that a parent signed in with email and password on a phone (rule 6).
 *
 * Handed to the phone at every email-and-password sign-in, and asked for at
 * every PIN sign-in, so a PIN works only on a phone where the parent has
 * typed their password at least once. It also means someone holding only
 * the household code cannot guess at the PIN, or use up its five tries.
 *
 * Nothing is stored: the ticket is a keyed hash of the parent's id and their
 * current password hash. A new password, whether changed or reset, retires
 * every ticket at once, so each phone needs the password again before its
 * PIN works. Pure: the key and both values are passed in.
 */
final class PinTicket
{
    private const PURPOSE = 'chorequest-parent-pin-ticket';

    public static function issue(string $key, int $parentId, string $passwordHash): string
    {
        $mac = hash_hmac('sha256', self::PURPOSE.'|'.$parentId.'|'.$passwordHash, $key, true);

        return rtrim(strtr(base64_encode($mac), '+/', '-_'), '=');
    }

    public static function matches(string $ticket, string $key, int $parentId, string $passwordHash): bool
    {
        return hash_equals(self::issue($key, $parentId, $passwordHash), $ticket);
    }
}
