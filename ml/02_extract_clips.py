"""M2: cut the training clips the manifest asks for.

    python ml/02_extract_clips.py --dry-run         # counts only, cuts nothing
    python ml/02_extract_clips.py --list-videos     # the EPIC videos to download
    python ml/02_extract_clips.py                   # cut everything not cut yet

Where it looks (all under ml/, none of it committed):

    labels/epic_kitchens_100/EPIC_100_train.csv, EPIC_100_validation.csv,
        EPIC_100_verb_classes.csv, EPIC_100_noun_classes.csv
    data/raw/epic_kitchens_100/<participant>/videos/<video_id>.MP4
    labels/kinetics_400/train.csv, validate.csv (or val.csv), test.csv
        (label, youtube_id, time_start, time_end, split)
    data/raw/kinetics_400/<split>/<youtube_id>_<start:06d>_<end:06d>.mp4
    data/raw/own/<household>/<chore key or other>/<any video>   (M10)

For EPIC-KITCHENS a row is a chore's when its verb is one of the chore's verbs
and one of the row's nouns is one of its nouns (a chore that lists no verbs, or
no nouns, matches on the other alone). A row two chores would both claim is
left out, since a clip labelled two ways teaches the model a contradiction; the
report lists which chores collide, so the manifest can be narrowed. For Kinetics the label decides. Your own
recordings are filed by folder.

Each clip is cut with FFmpeg into data/clips/<label>/, silent, 8 frames a
second, 256 pixels on its short side: the model looks at 192 or 224 pixels four
times a second, and anything more is disk. data/clips.csv lists them: clip,
source, household, start, end (seconds in the source; a whole video is timed
from 0), label, domain. The household is what 03 splits
by: the EPIC participant, the Kinetics video, or your H-number.

The count per chore is printed at the end, with thin classes marked, and your
own clips are tallied per chore and per home, so gaps show before training.
"""
import argparse
import ast
import csv
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

import pipeline as p

LABELS = p.ML / "labels"
EPIC_LABELS = LABELS / "epic_kitchens_100"
KINETICS_LABELS = LABELS / "kinetics_400"
VIDEO_SUFFIXES = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".3gp"}
MIN_SECONDS = 2.0
MAX_SECONDS = 60.0
THIN = 40


def seconds(stamp):
    """EPIC's 00:01:02.345 as seconds."""
    hours, minutes, rest = stamp.split(":")
    return int(hours) * 3600 + int(minutes) * 60 + float(rest)


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def class_keys(kind):
    path = EPIC_LABELS / f"EPIC_100_{kind}_classes.csv"
    return {int(row["id"]): row["key"] for row in read_csv(path)} if path.exists() else None


def epic_candidates(manifest):
    verbs, nouns = class_keys("verb"), class_keys("noun")
    files = [EPIC_LABELS / name for name in ("EPIC_100_train.csv", "EPIC_100_validation.csv")]
    if verbs is None or nouns is None or not all(f.exists() for f in files):
        print("EPIC-KITCHENS: label files not found under ml/labels/epic_kitchens_100/; skipped")
        return [], Counter()
    wants = []
    for chore in manifest["chores"]:
        for source in chore.get("sources", []):
            if source["dataset"] == "epic_kitchens_100":
                wants.append((chore["key"], set(source.get("verbs", [])), set(source.get("nouns", []))))
    found, ambiguous = [], Counter()
    for file in files:
        for row in read_csv(file):
            verb = verbs.get(int(row["verb_class"]))
            row_nouns = {nouns.get(int(n)) for n in ast.literal_eval(row["all_noun_classes"])}
            claims = {key for key, vs, ns in wants if (not vs or verb in vs) and (not ns or row_nouns & ns)}
            if len(claims) > 1:
                ambiguous[tuple(sorted(claims))] += 1
                continue
            if not claims:
                continue
            start, end = seconds(row["start_timestamp"]), seconds(row["stop_timestamp"])
            if end - start < MIN_SECONDS:
                continue
            participant = row["participant_id"]
            found.append({
                "label": claims.pop(),
                "source": "epic_kitchens_100",
                "household": f"epic-{participant}",
                "video": p.RAW / "epic_kitchens_100" / participant / "videos" / f"{row['video_id']}.MP4",
                "video_id": row["video_id"],
                "start": start,
                "end": min(end, start + MAX_SECONDS),
                "name": f"epic_{row['narration_id']}",
            })
    return found, ambiguous


def kinetics_candidates(manifest):
    files = [KINETICS_LABELS / f"{split}.csv" for split in ("train", "validate", "val", "test")]
    if not any(f.exists() for f in files):
        print("Kinetics-400: annotation files not found under ml/labels/kinetics_400/; skipped")
        return []
    wants = defaultdict(set)
    for chore in manifest["chores"]:
        for source in chore.get("sources", []):
            if source["dataset"] == "kinetics_400":
                for label in source.get("labels", []):
                    wants[label].add(chore["key"])
    found = []
    for file in files:
        if not file.exists():
            continue
        for row in read_csv(file):
            keys = wants.get(row["label"], set())
            if len(keys) != 1:
                continue
            start, end = int(float(row["time_start"])), int(float(row["time_end"]))
            youtube = row["youtube_id"]
            found.append({
                "label": next(iter(keys)),
                "source": "kinetics_400",
                "household": f"kinetics-{youtube}",
                "video": p.RAW / "kinetics_400" / row.get("split", file.stem) / f"{youtube}_{start:06d}_{end:06d}.mp4",
                "video_id": youtube,
                "start": None,
                "end": None,
                "name": f"kinetics_{youtube}_{start:06d}",
            })
    return found


def own_candidates(keys):
    root = p.RAW / "own"
    if not root.exists():
        print("Own recordings: data/raw/own/ not found; skipped")
        return [], []
    found, unknown = [], []
    for household in sorted(d for d in root.iterdir() if d.is_dir()):
        for folder in sorted(d for d in household.iterdir() if d.is_dir()):
            if folder.name not in keys:
                unknown.append(str(folder.relative_to(p.ML)))
                continue
            for video in sorted(folder.iterdir()):
                if video.suffix.lower() in VIDEO_SUFFIXES:
                    found.append({
                        "label": folder.name,
                        "source": "own",
                        "household": f"own-{household.name}",
                        "video": video,
                        "video_id": video.stem,
                        "start": None,
                        "end": None,
                        "name": f"own_{household.name}_{video.stem}",
                    })
    return found, unknown


def spread(candidates, limit):
    """At most limit clips per chore, taken in turn from each household, so
    one prolific participant does not become the whole class."""
    by_chore = defaultdict(lambda: defaultdict(list))
    for c in candidates:
        by_chore[c["label"]][c["household"]].append(c)
    kept = []
    for households in by_chore.values():
        queues = [list(v) for _, v in sorted(households.items())]
        taken = 0
        while queues and taken < limit:
            for queue in list(queues):
                if not queue:
                    queues.remove(queue)
                    continue
                kept.append(queue.pop(0))
                taken += 1
                if taken >= limit:
                    break
    return kept


def cut(candidate, out):
    """Silent, 8 frames a second, 256 on the short side, upright."""
    command = ["ffmpeg", "-v", "error", "-y"]
    if candidate["start"] is not None:
        command += ["-ss", f"{candidate['start']:.3f}", "-to", f"{candidate['end']:.3f}"]
    elif candidate["source"] == "own":
        command += ["-t", f"{MAX_SECONDS}"]
    scale = (f"fps={p.CLIP_FPS},"
             f"scale='if(gt(iw,ih),-2,{p.SHORT_SIDE})':'if(gt(iw,ih),{p.SHORT_SIDE},-2)'")
    command += ["-i", str(candidate["video"]), "-an", "-vf", scale,
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p", str(out)]
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(command, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="count and report; cut nothing")
    parser.add_argument("--list-videos", action="store_true", help="write data/epic_videos_needed.txt and stop")
    parser.add_argument("--max-per-chore", type=int, default=400, help="public clips kept per chore (default 400)")
    args = parser.parse_args()

    manifest = p.load_manifest()
    keys = p.class_keys(manifest)
    epic, ambiguous = epic_candidates(manifest)
    kinetics = kinetics_candidates(manifest)
    own, unknown = own_candidates(set(keys))
    public = spread(epic + kinetics, args.max_per_chore)
    chosen = public + own

    if args.list_videos:
        needed = sorted({c["video_id"] for c in public if c["source"] == "epic_kitchens_100"})
        p.DATA.mkdir(parents=True, exist_ok=True)
        (p.DATA / "epic_videos_needed.txt").write_text("\n".join(needed) + "\n", encoding="utf-8")
        print(f"{len(needed)} EPIC-KITCHENS videos are needed; listed in data/epic_videos_needed.txt")
        return

    if not args.dry_run:
        p.need_ffmpeg()
    rows, missing, failed = [], Counter(), Counter()
    for c in chosen:
        if not c["video"].exists():
            missing[c["source"]] += 1
            continue
        out = p.CLIPS / c["label"] / f"{c['name']}.mp4"
        if not args.dry_run and not out.exists():
            try:
                cut(c, out)
            except subprocess.CalledProcessError:
                failed[c["source"]] += 1
                out.unlink(missing_ok=True)
                continue
        # Whole videos (Kinetics, your own) are timed from the clip itself.
        start, end = c["start"], c["end"]
        if start is None:
            start, end = 0.0, (p.video_seconds(out) if not args.dry_run else 0.0)
        rows.append({
            "clip": str(out.relative_to(p.CLIPS).as_posix()),
            "source": c["source"],
            "household": c["household"],
            "start": f"{start:.3f}",
            "end": f"{end:.3f}",
            "label": c["label"],
            "domain": "own" if c["source"] == "own" else "public",
        })

    if not args.dry_run:
        p.CLIPS_CSV.parent.mkdir(parents=True, exist_ok=True)
        with open(p.CLIPS_CSV, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=p.CLIP_COLUMNS)
            writer.writeheader()
            writer.writerows(rows)

    report(keys, rows, chosen, missing, failed, ambiguous, unknown, args.dry_run)


def report(keys, rows, chosen, missing, failed, ambiguous, unknown, dry_run):
    counts = Counter(r["label"] for r in rows)
    wanted = Counter(c["label"] for c in chosen)
    print()
    print(f"{'chore':34} {'clips':>6} {'of':>6}")
    for key in keys:
        mark = "  <- thin" if counts[key] < THIN else ""
        print(f"{key:34} {counts[key]:>6} {wanted[key]:>6}{mark}")
    print(f"{'total':34} {sum(counts.values()):>6} {sum(wanted.values()):>6}")
    if missing:
        print("\nVideos not on disk, so not cut: " + ", ".join(f"{k} {v}" for k, v in missing.items()))
    if failed:
        print("FFmpeg could not cut: " + ", ".join(f"{k} {v}" for k, v in failed.items()))
    if ambiguous:
        print()
        print(f"EPIC rows that more than one chore claims, left out ({sum(ambiguous.values())}). The manifest's")
        print("verbs and nouns overlap here; narrowing them gives these chores their clips back:")
        for chores, count in ambiguous.most_common():
            print(f"  {count:6}  {' / '.join(chores)}")
    if unknown:
        print("Folders under data/raw/own/ that are not a chore key or 'other', skipped:")
        for folder in unknown:
            print(f"  {folder}")

    own = [r for r in rows if r["domain"] == "own"]
    if own:
        homes = sorted({r["household"] for r in own})
        tally = Counter((r["label"], r["household"]) for r in own)
        print("\nYour own clips, per chore and home (M10 asks for 40 per chore across 6 homes):")
        print(f"{'chore':34} " + " ".join(f"{h.removeprefix('own-'):>5}" for h in homes) + "  total")
        for key in keys:
            line = [tally[(key, h)] for h in homes]
            print(f"{key:34} " + " ".join(f"{n:>5}" for n in line) + f"  {sum(line):>5}")
    if dry_run:
        print("\nDry run: nothing was cut and data/clips.csv was not written.")


if __name__ == "__main__":
    main()
