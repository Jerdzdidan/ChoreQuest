"""Write the app's chore catalogue from ml/chore_manifest.json (CH-4).

    python ml/export_catalogue.py

Checks the manifest first (check_manifest.py) and writes nothing if it
fails. Writes backend/database/seeders/data/chores.json: the categories and,
for each chore, only what the server stores. ChoreTemplateSeeder reads that
file; run it again after every change here:

    cd backend && php artisan db:seed --class=ChoreTemplateSeeder
"""
import json
import os
import sys

from check_manifest import MANIFEST, check

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "backend", "database", "seeders", "data", "chores.json")

FIELDS = [
    "key", "name", "description", "icon", "category", "location",
    "min_age", "max_age", "difficulty", "verification_mode", "model_class",
    "min_active_seconds", "formerly",
]


def main():
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    problems = check(manifest)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        sys.exit(1)

    catalogue = {
        "_about": "Written by ml/export_catalogue.py from ml/chore_manifest.json. Edit the manifest, not this file.",
        "version": manifest["version"],
        "categories": manifest["categories"],
        "chores": [
            {**{field: chore[field] for field in FIELDS}, "default_points": chore["points"]}
            for chore in manifest["chores"]
        ],
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(catalogue, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {len(catalogue['chores'])} chores in {len(catalogue['categories'])} categories to {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
