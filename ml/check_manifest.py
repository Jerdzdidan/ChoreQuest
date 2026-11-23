"""Check ml/chore_manifest.json, the list of chores the app offers and the model learns.

    python ml/check_manifest.py

Exits with an error, listing every problem, if any chore has no dataset
source, or if the manifest is inconsistent in a way that would let the
catalogue and the model disagree. When a dataset's own label files are
present under ml/labels/<dataset>/, each label a chore names is also looked
up in them; without them only the shape is checked.
"""
import csv
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "chore_manifest.json")
LABELS = os.path.join(HERE, "labels")

LOCATIONS = {"kitchen", "bedroom", "study", "outdoor", "other"}
DIFFICULTIES = {"easy", "medium", "hard"}
MODES = {"lstm", "manual"}
KEY = re.compile(r"^[a-z][a-z0-9_]{1,59}$")


def epic_classes(kind):
    """EPIC-KITCHENS-100 class keys, from EPIC_100_<kind>_classes.csv, or None."""
    path = os.path.join(LABELS, "epic_kitchens_100", f"EPIC_100_{kind}_classes.csv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return {row["key"] for row in csv.DictReader(f)}


def kinetics_labels():
    """Kinetics-400 class names, one per line in kinetics_400_labels.txt, or None."""
    path = os.path.join(LABELS, "kinetics_400", "kinetics_400_labels.txt")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return {line.strip() for line in f if line.strip()}


def labels_of(source):
    return [*source.get("labels", []), *source.get("verbs", []), *source.get("nouns", [])]


def check(manifest):
    problems = []
    datasets = manifest.get("datasets", {})
    categories = {c["key"] for c in manifest.get("categories", [])}
    known = {
        ("epic_kitchens_100", "verbs"): epic_classes("verb"),
        ("epic_kitchens_100", "nouns"): epic_classes("noun"),
        ("kinetics_400", "labels"): kinetics_labels(),
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

        # The rule the catalogue rests on: every chore maps to at least one
        # class in a dataset the team can train from.
        sources = [s for s in chore.get("sources", []) if labels_of(s)]
        if not sources:
            say("no dataset source: every chore must map to at least one dataset class")
        for source in chore.get("sources", []):
            dataset = source.get("dataset")
            if dataset not in datasets:
                say(f"source dataset {dataset!r} is not in the dataset list")
            for field in ("labels", "verbs", "nouns"):
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
    lstm = sum(1 for c in chores if c["verification_mode"] == "lstm")
    checked = [name for name, ok in (("EPIC-KITCHENS-100", epic_classes("verb")), ("Kinetics-400", kinetics_labels())) if ok]
    print(f"{len(chores)} chores, {lstm} movement-checked and {len(chores) - lstm} checked by a parent, every one with a dataset source")
    print("labels looked up in: " + (", ".join(checked) if checked else "no label files under ml/labels yet (shape checked only)"))


if __name__ == "__main__":
    main()
