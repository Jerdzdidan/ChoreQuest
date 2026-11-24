"""Check ml/chore_manifest.json, the list of chores the app offers and the model learns.

    python ml/check_manifest.py

Exits with an error, listing every problem, if a movement-checked chore has no
first-person dataset source, or if the manifest is inconsistent in a way that
would let the catalogue and the model disagree. A chore with no source is
checked by a parent (manual): Phase 5 trains on first-person video only, and a
chore no first-person dataset shows cannot be learned.

Sources come in two kinds:
- EPIC-KITCHENS-100 verbs and nouns. When the dataset's own class files are
  present under ml/labels/epic_kitchens_100/, each one is looked up there.
- HomER v2: one of its six categories that hold chores, and words its videos'
  descriptions would use, for shortlisting (DS-2). Its labels are the team's
  own: ml/labels/homer_v2/segments.csv (video_id, start, end, chore_key, from
  10_label_homer.py). When that file is present, every chore_key in it must be
  a chore in the manifest, and the segments per chore are counted.
"""
import csv
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "chore_manifest.json")
LABELS = os.path.join(HERE, "labels")
SEGMENTS = os.path.join(LABELS, "homer_v2", "segments.csv")

LOCATIONS = {"kitchen", "bedroom", "study", "outdoor", "other"}
DIFFICULTIES = {"easy", "medium", "hard"}
MODES = {"lstm", "manual"}
KEY = re.compile(r"^[a-z][a-z0-9_]{1,59}$")
HOMER_CATEGORIES = {
    "Cleaning", "Dining Table Tasks", "Laundry & Garment Care",
    "Indoor Plant Activities", "Home Organization", "Food Preparation",
}


def epic_classes(kind):
    """EPIC-KITCHENS-100 class keys, from EPIC_100_<kind>_classes.csv, or None."""
    path = os.path.join(LABELS, "epic_kitchens_100", f"EPIC_100_{kind}_classes.csv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return {row["key"] for row in csv.DictReader(f)}


def homer_segments():
    """The team's HomER segments as rows, or None before there is a file."""
    if not os.path.exists(SEGMENTS):
        return None
    with open(SEGMENTS, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def is_source(source):
    """Whether a source names something to learn from."""
    if source.get("dataset") == "homer_v2":
        return bool(source.get("category")) and bool(source.get("describe"))
    return bool(source.get("verbs") or source.get("nouns"))


def check(manifest):
    problems = []
    datasets = manifest.get("datasets", {})
    categories = {c["key"] for c in manifest.get("categories", [])}
    known = {
        ("epic_kitchens_100", "verbs"): epic_classes("verb"),
        ("epic_kitchens_100", "nouns"): epic_classes("noun"),
    }

    keys, names, classes = set(), set(), []
    for chore in manifest.get("chores", []):
        key = chore.get("key", "?")
        say = lambda message: problems.append(f"{key}: {message}")

        if not KEY.match(key):
            say("key must be lower_snake_case")
        if key in keys:
            say("key used twice")
        keys.add(key)
        if chore.get("name") in names:
            say("name used twice")
        names.add(chore.get("name"))

        for field in ("name", "description", "icon"):
            if not chore.get(field):
                say(f"no {field}")
        if chore.get("category") not in categories:
            say(f"category {chore.get('category')!r} is not in the category list")
        if chore.get("location") not in LOCATIONS:
            say(f"location {chore.get('location')!r} is not a quest map place")
        if chore.get("difficulty") not in DIFFICULTIES:
            say(f"difficulty {chore.get('difficulty')!r}")
        lo, hi = chore.get("min_age"), chore.get("max_age")
        if not (isinstance(lo, int) and isinstance(hi, int) and 4 <= lo <= hi <= 10):
            say(f"ages {lo}-{hi} must sit within 4-10")
        if not (isinstance(chore.get("points"), int) and chore["points"] > 0):
            say("points must be a whole number above 0")

        mode = chore.get("verification_mode")
        if mode not in MODES:
            say(f"verification_mode {mode!r}")
        elif mode == "lstm":
            if not isinstance(chore.get("model_class"), int):
                say("an lstm chore needs a model_class")
            else:
                classes.append(chore["model_class"])
            if not (isinstance(chore.get("min_active_seconds"), int) and chore["min_active_seconds"] > 0):
                say("an lstm chore needs min_active_seconds above 0")
        else:
            if chore.get("model_class") is not None or chore.get("min_active_seconds") is not None:
                say("a manual chore has no model_class and no min_active_seconds")

        # The rule the catalogue rests on: the model only checks what a
        # first-person dataset the team can train from shows.
        if mode == "lstm" and not any(is_source(s) for s in chore.get("sources", [])):
            say("no dataset source: a movement-checked chore must map to a first-person dataset (or be manual)")
        for source in chore.get("sources", []):
            dataset = source.get("dataset")
            if dataset not in datasets:
                say(f"source dataset {dataset!r} is not in the dataset list")
            if dataset == "homer_v2":
                if source.get("category") not in HOMER_CATEGORIES:
                    say(f"HomER category {source.get('category')!r} is not one of the six that hold chores")
                words = source.get("describe")
                if not (isinstance(words, list) and words and all(isinstance(w, str) and w.strip() for w in words)):
                    say("a HomER source needs the words its description would use (describe)")
                continue
            for field in ("verbs", "nouns"):
                classes_known = known.get((dataset, field))
                if classes_known is None:
                    continue
                for label in source.get(field, []):
                    if label not in classes_known:
                        say(f"{dataset} has no {field[:-1]} class {label!r}")

    if sorted(classes) != list(range(len(classes))):
        problems.append(f"model_class numbers must run 0 to {len(classes) - 1} with none repeated, got {sorted(classes)}")
    if manifest.get("other_class") != len(classes):
        problems.append(f"other_class must be {len(classes)}, the class after the last chore")

    for number, row in enumerate(homer_segments() or [], start=2):
        if row.get("chore_key") not in keys and row.get("chore_key") != "other":
            problems.append(f"segments.csv line {number}: {row.get('chore_key')!r} is not a chore in the manifest")
        try:
            if not float(row["start"]) < float(row["end"]):
                problems.append(f"segments.csv line {number}: start must come before end")
        except (KeyError, TypeError, ValueError):
            problems.append(f"segments.csv line {number}: start and end must be seconds")

    return problems


def main():
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    problems = check(manifest)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        sys.exit(1)

    chores = manifest["chores"]
    lstm = [c for c in chores if c["verification_mode"] == "lstm"]
    unsourced = [c["key"] for c in chores if not any(is_source(s) for s in c.get("sources", []))]
    print(f"{len(chores)} chores, {len(lstm)} movement-checked and {len(chores) - len(lstm)} checked by a parent")
    if unsourced:
        print("no first-person source yet, so checked by a parent: " + ", ".join(unsourced))
    print("EPIC-KITCHENS labels looked up: " + ("yes" if epic_classes("verb") else "no class files under ml/labels yet (shape checked only)"))
    segments = homer_segments()
    if segments is None:
        print("HomER segments: none labelled yet (labels/homer_v2/segments.csv, from 10_label_homer.py)")
    else:
        counts = {}
        for row in segments:
            counts[row["chore_key"]] = counts.get(row["chore_key"], 0) + 1
        print(f"HomER segments: {len(segments)}, " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main()
