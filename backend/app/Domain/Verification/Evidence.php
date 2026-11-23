<?php

namespace App\Domain\Verification;

/**
 * A quest session's evidence summary (LS-8), as the server keeps it.
 *
 * Only the agreed keys are kept, each as the type it should be; anything
 * else the phone sends is dropped, so a newer or tampered app cannot fill
 * the column with something nobody reads. It never holds pictures. Pure: no
 * clock, no database.
 */
final class Evidence
{
    /** The largest summary accepted, in bytes. */
    public const MAX_BYTES = 8192;

    /** The longest timeline kept: one point every 5 seconds for an hour. */
    public const MAX_TIMELINE = 720;

    /** key => type */
    private const KEYS = [
        'mode' => 'mode',
        'model_version' => 'string',
        'chore_key' => 'string',
        'session_seconds' => 'int',
        'active_seconds' => 'int',
        'mean_probability' => 'probability',
        'max_probability' => 'probability',
        'matched_share' => 'probability',
        'timeline' => 'timeline',
        'scene_change' => 'float',
        'scene_fits' => 'bool',
        'camera' => 'string',
        'camera_flipped' => 'bool',
        'camera_fallback' => 'bool',
        'model_unavailable' => 'bool',
        'mean_model_ms' => 'int',
        'phone_model' => 'string',
        'started_at' => 'string',
        'finished_at' => 'string',
    ];

    /**
     * The summary with only the agreed keys, each cleaned to its type. Null
     * values and values of the wrong type are dropped.
     *
     * @param  array<string, mixed>  $raw
     * @return array<string, mixed>
     */
    public static function clean(array $raw): array
    {
        $clean = [];
        foreach (self::KEYS as $key => $type) {
            if (! array_key_exists($key, $raw) || $raw[$key] === null) {
                continue;
            }
            $value = self::cast($raw[$key], $type);
            if ($value !== null) {
                $clean[$key] = $value;
            }
        }

        return $clean;
    }

    private static function cast(mixed $value, string $type): mixed
    {
        return match ($type) {
            'mode' => in_array($value, ['lstm', 'manual'], true) ? $value : null,
            'string' => is_string($value) ? mb_substr($value, 0, 60) : null,
            'int' => is_numeric($value) ? max(0, (int) $value) : null,
            'float' => is_numeric($value) ? max(0.0, (float) $value) : null,
            'probability' => is_numeric($value) ? min(1.0, max(0.0, (float) $value)) : null,
            'bool' => is_bool($value) ? $value : null,
            'timeline' => is_array($value) ? self::timeline($value) : null,
            default => null,
        };
    }

    /**
     * One point every 5 seconds: [seconds, probability] pairs, kept in order
     * and capped in length.
     *
     * @param  array<mixed>  $points
     * @return list<array{0: int, 1: float}>
     */
    private static function timeline(array $points): array
    {
        $kept = [];
        foreach (array_slice(array_values($points), 0, self::MAX_TIMELINE) as $point) {
            if (is_array($point) && count($point) === 2 && is_numeric($point[0] ?? null) && is_numeric($point[1] ?? null)) {
                $kept[] = [max(0, (int) $point[0]), min(1.0, max(0.0, (float) $point[1]))];
            }
        }

        return $kept;
    }
}
