"""M3, DS-4: split by person and household, never by clip.

    python ml/03_make_splits.py [--seed 7] [--val 0.15] [--test 0.15]

Writes data/splits.json: {"train": [...], "val": [...], "test": [...]}, lists
of households. A person or home in training must not appear in testing, or
every number in Chapter 4 is flattering and wrong, so the split is made over
households (EPIC participants, HomER people, your H-numbers), and the script
stops with an error if any household ends up in two splits.

HomER v2 has no participant ids. Its household is the person the labeller
named in 10_label_homer.py ("Recorded by"); a video no one matched to another
counts as its own person. Two videos of one person the labeller did not
recognise could still land on both sides: say so in Chapter 3.

Your own homes, HomER's people and EPIC's participants are each split on their
own, so every split holds some of each: your in-domain clips matter most, and
HomER is the closest public match to a strapped-on phone. Within each group,
households are shuffled with the seed and dealt out until each split holds
about its share of clips.
"""
import argparse
import random
from collections import Counter

import pipeline as p


def deal(households, sizes, val, test, rng):
    """Households into train, val and test, about val and test of the clips."""
    order = sorted(households)
    rng.shuffle(order)
    total = sum(sizes[h] for h in order)
    split = {"train": [], "val": [], "test": []}
    filled = Counter()
    for household in order:
        # The split furthest below its share takes the next household.
        want = {"val": val * total - filled["val"], "test": test * total - filled["test"]}
        if len(order) >= 3 and not split["val"]:
            name = "val"
        elif len(order) >= 3 and not split["test"]:
            name = "test"
        else:
            name = max(want, key=want.get) if max(want.values()) > 0 else "train"
        split[name].append(household)
        filled[name] += sizes[household]
    return split


def check(splits):
    seen = {}
    for name, households in splits.items():
        for household in households:
            if household in seen:
                p.fail(f"household {household} is in both {seen[household]} and {name}")
            seen[household] = name


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--val", type=float, default=0.15)
    parser.add_argument("--test", type=float, default=0.15)
    args = parser.parse_args()

    clips = p.read_clips()
    sizes = Counter(c["household"] for c in clips)
    rng = random.Random(args.seed)
    own = {c["household"] for c in clips if c["domain"] == "own"}
    homer = {h for h in sizes if h.startswith("homer-")} - own
    public = set(sizes) - own - homer

    splits = {"train": [], "val": [], "test": []}
    for group in (own, homer, public):
        if group:
            for name, households in deal(group, sizes, args.val, args.test, rng).items():
                splits[name] += households
    check(splits)
    p.write_json(p.SPLITS_JSON, {name: sorted(households) for name, households in splits.items()})

    print(f"{'split':6} {'homes':>6} {'own homes':>10} {'HomER people':>13} {'clips':>7} {'own clips':>10} {'HomER clips':>12}")
    for name, households in splits.items():
        chosen = set(households)
        rows = [c for c in clips if c["household"] in chosen]
        print(f"{name:6} {len(chosen):>6} {len(chosen & own):>10} {len(chosen & homer):>13} {len(rows):>7} "
              f"{sum(c['domain'] == 'own' for c in rows):>10} {sum(c['household'] in homer for c in rows):>12}")
    labels = sorted({c["label"] for c in clips})
    empty = [(name, label) for name, households in splits.items() for label in labels
             if not any(c["label"] == label and c["household"] in set(households) for c in clips)]
    if empty:
        print("\nChores with no clip in a split (record more homes, or the numbers for them mean little):")
        for name, label in empty:
            print(f"  {name}: {label}")
    print(f"\nWrote {p.SPLITS_JSON.relative_to(p.ML)}. No household is in two splits.")


if __name__ == "__main__":
    main()
