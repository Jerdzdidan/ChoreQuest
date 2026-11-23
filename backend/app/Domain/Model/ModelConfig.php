<?php

namespace App\Domain\Model;

use RuntimeException;

/**
 * The movement model's thresholds (BE-6): the minimum class probability and
 * seconds of matching movement before Done appears, per chore with defaults,
 * the bands that grade a session's evidence for the parent, and the longest
 * an alarm may ring.
 *
 * Read from resources/model_config.json, which the calibration script
 * writes (M7). They are not per-child settings: they live with the model,
 * and a change reaches every phone at its next app open with no rebuild.
 * This replaces the per-child confidence sliders and keeps their purpose:
 * thresholds tunable from outside the app.
 */
final class ModelConfig
{
    /** @var array<string, mixed>|null */
    private static ?array $data = null;

    public static function path(): string
    {
        return resource_path('model_config.json');
    }

    /** @return array<string, mixed> */
    public static function all(): array
    {
        if (self::$data === null) {
            $raw = @file_get_contents(self::path());
            if ($raw === false) {
                throw new RuntimeException('resources/model_config.json is missing.');
            }
            self::$data = json_decode($raw, true, flags: JSON_THROW_ON_ERROR);
        }

        return self::$data;
    }

    /** Forget the file read, so the next call reads it again. */
    public static function reload(): void
    {
        self::$data = null;
    }

    /**
     * What a phone receives: everything but the note to whoever edits it.
     * The per-chore map stays a JSON object even when empty; PHP would
     * otherwise send an empty one as a list.
     */
    public static function forPhones(): array
    {
        $config = array_diff_key(self::all(), ['_about' => true]);
        $config['chores'] = (object) ($config['chores'] ?? []);

        return $config;
    }

    /** @return array{probability: float, active_seconds: int, scene_change: float} */
    public static function evidenceBands(): array
    {
        $bands = self::all()['evidence_bands'] ?? [];

        return [
            'probability' => (float) ($bands['probability'] ?? 0.6),
            'active_seconds' => (int) ($bands['active_seconds'] ?? 20),
            'scene_change' => (float) ($bands['scene_change'] ?? 0.1),
        ];
    }

    public static function maxRingMinutes(): int
    {
        return (int) (self::all()['max_ring_minutes'] ?? 10);
    }
}
