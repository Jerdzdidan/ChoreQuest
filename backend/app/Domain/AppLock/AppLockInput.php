<?php

namespace App\Domain\AppLock;

/**
 * What App Lock accepts from a phone (AL-2): the phone's own key and an
 * Android package name. Shared by every App Lock route so they cannot
 * disagree about what a phone or an app is.
 */
final class AppLockInput
{
    /**
     * ChoreQuest itself (applicationId in android/app/build.gradle.kts).
     * Locking it would put the lock screen behind itself, so no rule may
     * name it.
     */
    public const OWN_PACKAGE = 'com.chorequest';

    /** The key the phone makes for itself. */
    public const DEVICE_KEY_PATTERN = '/^[A-Za-z0-9_-]{8,64}$/';

    /**
     * Android's form: two or more dot-separated parts, each starting with
     * a letter, such as com.android.settings.
     */
    public const PACKAGE_PATTERN = '/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/';

    /** @return list<string> */
    public static function deviceKey(): array
    {
        return ['required', 'string', 'regex:'.self::DEVICE_KEY_PATTERN];
    }

    /** @return list<string> */
    public static function package(): array
    {
        return ['required', 'string', 'max:150', 'regex:'.self::PACKAGE_PATTERN];
    }
}
