"""DS-2: fetch HomER v2's metadata and shortlist the videos that may show a chore.

    python ml/00_intake.py              # fetch (or refresh) and shortlist
    python ml/00_intake.py --offline    # shortlist again from the saved copy

HomER v2 (Toloka, CC BY 4.0) holds 765 first-person household videos, about
100 hours, from 420 people. It ships links, not videos, and the links are
signed: they expire. This script saves every row, links included, to
data/homer_v2/videos.json (never committed: the links are as good as a key
while they last). Run it again whenever a download says a link has expired;
nothing else needs redoing.

The rows come from Hugging Face's dataset viewer, the same rows as the
dataset's parquet file, as JSON, so no parquet library is needed.

Then the shortlist, data/homer_v2/shortlist.csv: only the six categories that
hold chores, and of those only the videos whose description uses a word the
manifest gives a chore for that category (its HomER "describe" words). That is
what the team watches and labels (10_label_homer.py). A video is 146 MB to
1 GB, so nothing is downloaded here: labelling streams it, and
02_extract_clips.py downloads only the labelled ones, one at a time, cuts
them and deletes the original.
"""
import argparse
import datetime
import json
import re
import time
import urllib.error
import urllib.request

import pipeline as p

PAGE = 100
SHORTLIST_COLUMNS = ["video_id", "category", "chores", "duration_sec", "size_mb", "description"]


def fetch_rows(url=p.HOMER_ROWS, opener=urllib.request.urlopen):
    """Every row of HomER v2, a page at a time."""
    rows, offset, total = [], 0, None
    while total is None or offset < total:
        page_url = f"{url}&offset={offset}&length={PAGE}"
        for attempt in range(4):
            try:
                with opener(page_url, timeout=60) as response:
                    page = json.load(response)
                break
            except (urllib.error.URLError, TimeoutError) as e:
                if attempt == 3:
                    p.fail(f"could not reach the dataset viewer ({e}); try again later")
                time.sleep(5 * (attempt + 1))
        total = page["num_rows_total"]
        for item in page["rows"]:
            if item.get("truncated_cells"):
                p.fail(f"row {item['row_idx']} came back with cells cut short ({item['truncated_cells']}); "
                       "its link would not work. Download the dataset's parquet file instead.")
            rows.append(item["row"])
        if not page["rows"]:
            break
        offset += len(page["rows"])
    return rows


def shortlist(rows, manifest):
    """Videos in a chore category whose description uses one of a chore's
    words for that category, with the chores it may show."""
    wants = {}
    for chore in manifest["chores"]:
        for source in chore.get("sources", []):
            if source.get("dataset") == "homer_v2":
                code = p.HOMER_CATEGORY_CODES[source["category"]]
                patterns = [re.compile(r"\b" + re.escape(w.lower()) + r"\b") for w in source["describe"]]
                wants.setdefault(code, []).append((chore["key"], patterns))
    out = []
    for row in rows:
        description = (row.get("description") or "").lower()
        chores = sorted({key for key, patterns in wants.get(row.get("category"), [])
                         if any(pattern.search(description) for pattern in patterns)})
        if chores:
            out.append({
                "video_id": row["id"],
                "category": row["category"],
                "chores": ";".join(chores),
                "duration_sec": row.get("duration_sec", ""),
                "size_mb": row.get("size_mb", ""),
                "description": row.get("description", ""),
            })
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--offline", action="store_true", help="shortlist again from data/homer_v2/videos.json")
    args = parser.parse_args()

    manifest = p.load_manifest()
    if args.offline:
        rows = list(p.homer_videos().values())
    else:
        rows = fetch_rows()
        p.HOMER_DIR.mkdir(parents=True, exist_ok=True)
        p.write_json(p.HOMER_VIDEOS, {
            "dataset": p.HOMER_DATASET,
            "fetched_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "rows": rows,
        })
        print(f"Saved {len(rows)} videos' metadata to {p.HOMER_VIDEOS.relative_to(p.ML)} (links refreshed).")

    chosen = shortlist(rows, manifest)
    p.write_rows(p.HOMER_SHORTLIST, SHORTLIST_COLUMNS, chosen)

    in_categories = [r for r in rows if r.get("category") in p.HOMER_CATEGORY_CODES.values()]
    hours = sum(float(r["duration_sec"] or 0) for r in chosen) / 3600
    gigabytes = sum(float(r["size_mb"] or 0) for r in chosen) / 1024
    print(f"{len(in_categories)} videos are in the six chore categories; {len(chosen)} are shortlisted "
          f"({hours:.1f} hours to watch, {gigabytes:.1f} GB if every one were downloaded).")
    per_chore = {}
    for row in chosen:
        for key in row["chores"].split(";"):
            per_chore[key] = per_chore.get(key, 0) + 1
    print(f"\n{'chore':34} {'videos':>6}")
    for chore in manifest["chores"]:
        if any(s.get("dataset") == "homer_v2" for s in chore.get("sources", [])):
            print(f"{chore['key']:34} {per_chore.get(chore['key'], 0):>6}")
    print(f"\nWrote {p.HOMER_SHORTLIST.relative_to(p.ML)}. Label it with 10_label_homer.py.")


if __name__ == "__main__":
    main()
