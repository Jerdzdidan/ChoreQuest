<?php

namespace App\Domain\AppLock;

/**
 * Proof that a report about App Lock comes from the phone it was turned on
 * for (AL-4).
 *
 * The phone's watcher reports without anyone signed in: the phone may be
 * signed in as a child, a grown-up or no one. So when a parent turns App
 * Lock on, the phone is given this ticket instead of a token. It can do
 * one thing: report on that one phone. Nothing about it is stored but the
 * salt; a keyed hash of the household, the phone and the salt. Pure: the
 * key and every value are passed in.
 */
final class PhoneTicket
{
    private const PURPOSE = 'chorequest-app-lock-phone-ticket';

    public static function issue(string $key, int $householdId, string $deviceKey, string $salt): string
    {
        $mac = hash_hmac('sha256', self::PURPOSE.'|'.$householdId.'|'.$deviceKey.'|'.$salt, $key, true);

        return rtrim(strtr(base64_encode($mac), '+/', '-_'), '=');
    }

    public static function matches(string $ticket, string $key, int $householdId, string $deviceKey, string $salt): bool
    {
        return hash_equals(self::issue($key, $householdId, $deviceKey, $salt), $ticket);
    }
}
