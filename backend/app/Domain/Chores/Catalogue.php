<?php

namespace App\Domain\Chores;

use RuntimeException;

/**
 * The chore catalogue as ml/chore_manifest.json defines it, read from the
 * copy ml/export_catalogue.py writes for the server
 * (database/seeders/data/chores.json).
 *
 * One source for the seeder, which writes the chores, and for the catalogue
 * API, which names the categories a parent picks from, so the app never keeps
 * a list of its own.
 */
final class Catalogue
{
    /** The category a parent's own chores belong to, last in every list. */
    public const CUSTOM = 'custom';

    /** @var array{categories: list<array{key: string, name: string}>, chores: list<array<string, mixed>>}|null */
    private static ?array $data = null;

    public static function path(): string
    {
        return database_path('seeders/data/chores.json');
    }

    /** @return array{categories: list<array{key: string, name: string}>, chores: list<array<string, mixed>>} */
    public static function data(): array
    {
        if (self::$data === null) {
            $raw = @file_get_contents(self::path());
            if ($raw === false) {
                throw new RuntimeException('The chore catalogue is missing. Run python ml/export_catalogue.py.');
            }
            self::$data = json_decode($raw, true, flags: JSON_THROW_ON_ERROR);
        }

        return self::$data;
    }

    /**
     * Every category a parent can choose from, in the manifest's order, then
     * Custom chore.
     *
     * @return list<array{key: string, name: string}>
     */
    public static function categories(): array
    {
        return [
            ...array_map(fn (array $c) => ['key' => $c['key'], 'name' => $c['name']], self::data()['categories']),
            ['key' => self::CUSTOM, 'name' => 'Custom chore'],
        ];
    }

    /** @return list<array<string, mixed>> */
    public static function chores(): array
    {
        return self::data()['chores'];
    }
}
