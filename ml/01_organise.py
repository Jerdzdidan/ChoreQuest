"""
Builds the train / validation / test split, holding out WHOLE HOUSEHOLDS.

    python 01_organise.py --test-households H09,H10 --val-households H08

Chapter 2 promises a test set drawn from "households not represented in the
training data". That sentence is a methodological commitment, and it is easy to
break by accident: pool every photograph, split at random, and pictures of the
same bed in the same room land on both sides. Accuracy then comes out inflated,
and a panellist who understands convolutional networks will ask about it.

So the split is by household, never by photograph, and this script refuses to
write a split it cannot vouch for. It checks three things:

  1. No household appears in more than one split. Structural, and the reason
     the whole thing is arranged around household folders.

  2. No photograph appears in two splits, by file hash. Catches the same image
     copied into two household folders.

  3. No photograph appears in two splits, by perceptual hash. Catches the same
     picture re-saved or resized before being copied, which a file hash misses
     entirely. This is the one that actually protects the claim.

Any of the three failing stops the run with a non-zero exit and writes nothing.
"""

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "dataset" / "manifest.csv"
SPLITS = ROOT / "dataset" / "splits"

CHORES = ("made_bed", "cleared_table", "swept_floor")
STATES = ("done", "not_done")

# Two 64-bit perceptual hashes within this Hamming distance are treated as the
# same photograph. Zero would only catch byte-identical re-encodes; 5 catches a
# resize or a quality change without flagging two genuinely different beds.
AHASH_TOLERANCE = 5


def hamming(a: str, b: str) -> int:
    return bin(int(a, 16) ^ int(b, 16)).count("1")


def load() -> list[dict]:
    if not MANIFEST.exists():
        sys.exit(f"no manifest at {MANIFEST}. Run 00_intake.py first.")
    with MANIFEST.open(newline="", encoding="utf8") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        sys.exit("the manifest is empty.")
    return rows


def parse_list(value: str | None) -> set[str]:
    if not value:
        return set()
    return {h.strip().upper() for h in value.split(",") if h.strip()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--test-households", required=True,
                    help="comma separated, e.g. H09,H10")
    ap.add_argument("--val-households", default="",
                    help="comma separated; omit to carve validation from train")
    args = ap.parse_args()

    rows = load()
    all_households = sorted({r["household"] for r in rows})

    test_h = parse_list(args.test_households)
    val_h = parse_list(args.val_households)
    train_h = set(all_households) - test_h - val_h

    unknown = (test_h | val_h) - set(all_households)
    if unknown:
        return fail(f"households not in the manifest: {', '.join(sorted(unknown))}")

    if not train_h:
        return fail("no households left for training.")
    if not test_h:
        return fail("no households held out for testing.")

    assignment = {}
    for h in train_h:
        assignment[h] = "train"
    for h in val_h:
        assignment[h] = "val"
    for h in test_h:
        assignment[h] = "test"

    # ---- guard 1: a household in two splits ----
    overlap = (test_h & train_h) | (val_h & train_h) | (test_h & val_h)
    if overlap:
        return refuse(f"household(s) {', '.join(sorted(overlap))} appear in more than one split")

    buckets = defaultdict(list)
    for r in rows:
        buckets[assignment[r["household"]]].append(r)

    # ---- guard 2: identical file in two splits ----
    by_hash = defaultdict(set)
    for split, items in buckets.items():
        for r in items:
            by_hash[r["file_sha256"]].add(split)

    dupes = {h: s for h, s in by_hash.items() if len(s) > 1}
    if dupes:
        first = next(iter(dupes))
        offenders = [r["filename"] for r in rows if r["file_sha256"] == first]
        return refuse(
            f"{len(dupes)} identical image(s) appear in more than one split.\n"
            f"  first: {' and '.join(offenders[:2])}"
        )

    # ---- guard 3: the same picture, re-saved, in two splits ----
    train_hashes = [(r["ahash"], r["filename"]) for r in buckets["train"]]
    leaks = []
    for split in ("val", "test"):
        for r in buckets[split]:
            for th, tname in train_hashes:
                if hamming(r["ahash"], th) <= AHASH_TOLERANCE:
                    leaks.append((r["filename"], tname, split))
                    break

    if leaks:
        lines = "\n".join(f"  {a}  ~=  {b}  ({s} vs train)" for a, b, s in leaks[:8])
        more = f"\n  ...and {len(leaks) - 8} more" if len(leaks) > 8 else ""
        return refuse(
            f"{len(leaks)} image(s) held out are near-identical to training images.\n"
            f"{lines}{more}\n"
            "  The same photograph has been filed under two households, or two\n"
            "  households photographed the same room. Either way the held-out\n"
            "  claim in Chapter 2 does not hold until this is resolved."
        )

    # ---- all clear ----
    SPLITS.mkdir(parents=True, exist_ok=True)
    for split, items in buckets.items():
        path = SPLITS / f"{split}.csv"
        with path.open("w", newline="", encoding="utf8") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) + ["split"])
            writer.writeheader()
            for r in items:
                writer.writerow({**r, "split": split})

    report(buckets, assignment)
    print("\nsplit written to dataset/splits/. All three leakage guards passed.")
    return 0


def report(buckets, assignment) -> None:
    print(f"{'split':<8}{'households':<28}{'images':>8}")
    print("-" * 46)
    for split in ("train", "val", "test"):
        hh = sorted(h for h, s in assignment.items() if s == split)
        n = len(buckets.get(split, []))
        print(f"{split:<8}{', '.join(hh) or '-':<28}{n:>8}")

    print(f"\n{'':<24}", end="")
    for split in ("train", "val", "test"):
        print(f"{split:>12}", end="")
    print()

    for chore in CHORES:
        for state in STATES:
            print(f"{chore + '/' + state:<24}", end="")
            for split in ("train", "val", "test"):
                n = sum(1 for r in buckets.get(split, [])
                        if r["chore"] == chore and r["state"] == state)
                mark = " !" if n == 0 else ""
                print(f"{str(n) + mark:>12}", end="")
            print()

    empty = [
        (c, s, sp) for sp in ("train", "val", "test") for c in CHORES for s in STATES
        if buckets.get(sp) is not None
        and sum(1 for r in buckets.get(sp, []) if r["chore"] == c and r["state"] == s) == 0
    ]
    if empty:
        print("\n  ! a class is missing from a split. The model cannot be scored on a")
        print("    class the test set does not contain, and cannot learn one the")
        print("    training set does not contain.")


def refuse(message: str) -> int:
    print("\nREFUSED -- nothing written.\n", file=sys.stderr)
    print(message, file=sys.stderr)
    return 2


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
