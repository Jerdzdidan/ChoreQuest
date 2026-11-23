<?php

namespace Database\Seeders;

use App\Domain\Chores\Catalogue;
use App\Models\ChoreTemplate;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/**
 * The age-graded chore catalogue for children aged 4 to 10, from
 * ml/chore_manifest.json by way of database/seeders/data/chores.json
 * (written by ml/export_catalogue.py). Edit the manifest, not this file.
 *
 * A chore is in the catalogue only if it maps to a class in a dataset the
 * model can be trained from; ml/check_manifest.py enforces that. Ages follow
 * the progression in Chapter 2: ages 4-5 tidy and put away under supervision,
 * ages 6-7 take on routine upkeep, ages 8-10 handle water, heat-free food
 * handling and the outdoors.
 *
 * Each chore is updated or created by its manifest key. A chore that
 * predates keys is found by its name, or by a name it had before ("formerly"
 * in the manifest), so its assignments and history carry over. Any catalogue
 * chore the manifest no longer lists is retired, never deleted: assignments
 * and submissions cascade-delete with their template. A parent's custom
 * chores are never touched. Running it twice changes nothing the second
 * time.
 *
 * has_visible_end_state and verification_class are left as they are; only
 * the old single-photo flow reads them.
 */
class ChoreTemplateSeeder extends Seeder
{
    public function run(): void
    {
        DB::transaction(function () {
            $keys = [];

            foreach (Catalogue::chores() as $row) {
                $template = ChoreTemplate::where('key', $row['key'])->first()
                    ?? ChoreTemplate::whereNull('key')
                        ->where('is_custom', false)
                        ->whereIn('name', [$row['name'], ...$row['formerly']])
                        ->orderBy('id')
                        ->first()
                    ?? new ChoreTemplate;

                $template->fill([
                    'key' => $row['key'],
                    'name' => $row['name'],
                    'description' => $row['description'],
                    'icon' => $row['icon'],
                    'category' => $row['category'],
                    'location' => $row['location'],
                    'min_age' => $row['min_age'],
                    'max_age' => $row['max_age'],
                    'default_points' => $row['default_points'],
                    'difficulty' => $row['difficulty'],
                    'verification_mode' => $row['verification_mode'],
                    'model_class' => $row['model_class'],
                    'min_active_seconds' => $row['min_active_seconds'],
                    'is_custom' => false,
                    'retired_at' => null,
                ])->save();

                $keys[] = $row['key'];
            }

            ChoreTemplate::query()
                ->where('is_custom', false)
                ->whereNull('retired_at')
                ->where(fn ($q) => $q->whereNull('key')->orWhereNotIn('key', $keys))
                ->update(['retired_at' => now()]);
        });
    }
}
