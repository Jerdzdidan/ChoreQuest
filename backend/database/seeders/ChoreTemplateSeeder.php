<?php

namespace Database\Seeders;

use App\Models\ChoreTemplate;
use Illuminate\Database\Seeder;

/**
 * The age-graded chore catalogue for children aged 4 to 10.
 *
 * Ages follow the progression described in Chapter 2: ages 4-5 tidy and put
 * away under supervision, ages 6-7 take on routine upkeep, ages 8-10 handle
 * tasks involving water, heat-free food handling and the outdoors.
 *
 * `has_visible_end_state` marks chores a single photograph could show as
 * finished. `verification_class` marks the three the model is actually trained
 * for in Phase 5 -- everything else, including photographable chores, goes to
 * the parent for review.
 *
 * The proponents should revise this list against their own households before
 * it is used in the field.
 */
class ChoreTemplateSeeder extends Seeder
{
    public function run(): void
    {
        foreach ($this->catalogue() as $row) {
            ChoreTemplate::updateOrCreate(['name' => $row['name']], $row);
        }
    }

    private function catalogue(): array
    {
        return [
            // ---------- Ages 4-5: tidying, always alongside an adult ----------
            $this->t('Put the toys away', 'Return toys to the toy box or shelf', 'toys', 'tidying', 4, 6, 2, true),
            $this->t('Put clothes in the hamper', 'Dirty clothes go into the laundry basket', 'basket', 'tidying', 4, 7, 2, true),
            $this->t('Arrange the slippers', 'Line up the slippers neatly by the door', 'slippers', 'tidying', 4, 7, 2, true),
            $this->t('Put the books back', 'Return books to the shelf', 'books', 'tidying', 4, 7, 2, true),
            $this->t('Throw rubbish in the bin', 'Put your wrappers and scraps in the bin', 'bin', 'tidying', 4, 6, 1, false),
            $this->t('Fix the pillows', 'Arrange the pillows on the bed', 'pillow', 'bedroom', 4, 6, 2, true),
            $this->t('Feed the pet', 'Give the pet its food and fresh water', 'pet', 'care', 4, 10, 3, false),

            // ---------- Ages 6-7: routine upkeep ----------
            $this->t('Make the bed', 'Straighten the sheet and arrange the pillows', 'bed', 'bedroom', 6, 10, 5, true, 'made_bed'),
            $this->t('Set the table', 'Lay out the plates, glasses and spoons before a meal', 'plate', 'kitchen', 6, 10, 4, true),
            $this->t('Clear the table', 'Take the dishes off the table after eating and wipe it down', 'table', 'kitchen', 6, 10, 5, true, 'cleared_table'),
            $this->t('Sweep the floor', 'Sweep one room and collect the dirt into the dustpan', 'broom', 'cleaning', 6, 10, 5, true, 'swept_floor'),
            $this->t('Water the plants', 'Water the plants outside or on the windowsill', 'plant', 'care', 6, 10, 3, false),
            $this->t('Fold the small clothes', 'Fold the towels and small clothes and stack them neatly', 'fold', 'laundry', 6, 10, 4, true),
            $this->t('Wipe the windowsills', 'Wipe the dust off the windowsills with a damp cloth', 'cloth', 'cleaning', 6, 10, 3, true),
            $this->t('Put away the groceries', 'Help put the shopping into the cupboard and the fridge', 'groceries', 'kitchen', 6, 10, 4, true),

            // ---------- Ages 8-10: water, food handling, outdoors ----------
            $this->t('Wash the dishes', 'Wash the dishes and stack them on the rack to dry', 'dishes', 'kitchen', 8, 10, 8, true),
            $this->t('Mop the floor', 'Mop one room after sweeping it', 'mop', 'cleaning', 8, 10, 7, true),
            $this->t('Take out the rubbish', 'Take the bag out to the collection point', 'trash', 'cleaning', 8, 10, 4, false),
            $this->t('Hang the laundry', 'Hang the washing out on the line', 'laundry', 'laundry', 8, 10, 6, true),
            $this->t('Take in the laundry', 'Bring the dry washing in off the line and fold it', 'laundry', 'laundry', 8, 10, 6, true),
            $this->t('Put away your clothes', 'Put your folded clothes into the cabinet', 'wardrobe', 'laundry', 8, 10, 5, true),
            $this->t('Wash the rice', 'Measure the rice and rinse it ready for cooking', 'rice', 'kitchen', 8, 10, 4, false),
            $this->t('Clean the bathroom sink', 'Scrub and rinse the bathroom sink', 'sink', 'cleaning', 8, 10, 6, true),
            $this->t('Tidy the shoe rack', 'Arrange all the shoes neatly on the rack', 'shoes', 'tidying', 8, 10, 4, true),
            $this->t('Prepare a simple snack', 'Prepare a snack that needs no stove, and clean up after', 'snack', 'kitchen', 8, 10, 5, false),
        ];
    }

    private function t(
        string $name,
        string $description,
        string $icon,
        string $category,
        int $minAge,
        int $maxAge,
        int $points,
        bool $visibleEndState,
        ?string $verificationClass = null,
    ): array {
        return [
            'name' => $name,
            'description' => $description,
            'icon' => $icon,
            'category' => $category,
            'min_age' => $minAge,
            'max_age' => $maxAge,
            'default_points' => $points,
            'has_visible_end_state' => $visibleEndState,
            'verification_class' => $verificationClass,
        ];
    }
}
