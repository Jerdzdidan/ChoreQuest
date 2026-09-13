"""
Files one household's chore photographs into the dataset and records them.

    python 00_intake.py --household H03 --chore made_bed --state done <folder>

The layout it builds:

    ml/dataset/raw/<household>/<chore>/<state>/<household>_<chore>_<state>_NNNN.jpg
    ml/dataset/manifest.csv

Three things happen on the way in, and each is deliberate.

EXIF is stripped. A photograph taken on a phone inside a home carries GPS
coordinates, the capture time, and the device identifier. These are pictures of
children's bedrooms, and the study cites the Data Privacy Act of 2012, so that
metadata is removed at intake rather than trusted to be ignored later. The image
is re-encoded from pixel data alone.

Households are numbered, not named. The folder is H01, H02 and so on. Keep the
mapping from a number to a family on paper with the consent forms, never in the
repository.

Images are downscaled to 640px on the long edge. MobileNetV2 trains at 224x224,
so anything larger is storage and copying time for detail the model discards.

Chores must be one of the three classes the model is trained for. The catalogue
in the backend marks these with a verification_class; nothing else has one, and
photographs of other chores are not training data for this study.
"""

import argparse
import csv
import hashlib
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is missing. Run: pip install -r requirements.txt")

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "dataset" / "raw"
MANIFEST = ROOT / "dataset" / "manifest.csv"

CHORES = ("made_bed", "cleared_table", "swept_floor")
STATES = ("done", "not_done")
SUFFIXES = {".jpg", ".jpeg", ".png", ".heic", ".webp", ".bmp"}
MAX_EDGE = 640

FIELDS = [
    "household", "chore", "state", "filename",
    "file_sha256", "ahash", "width", "height", "source_name",
]


def average_hash(img: Image.Image) -> str:
    """
    A small perceptual fingerprint, used in 01_organise.py to notice the same
    photograph filed under two households. A plain file hash would miss it,
    because re-saving a copy changes the bytes but not the picture.
    """
    small = img.convert("L").resize((8, 8), Image.Resampling.LANCZOS)
    pixels = small.tobytes()
    mean = sum(pixels) / len(pixels)
    bits = "".join("1" if p > mean else "0" for p in pixels)
    return f"{int(bits, 2):016x}"


def load_manifest() -> list[dict]:
    if not MANIFEST.exists():
        return []
    with MANIFEST.open(newline="", encoding="utf8") as fh:
        return list(csv.DictReader(fh))


def write_manifest(rows: list[dict]) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with MANIFEST.open("w", newline="", encoding="utf8") as fh:
        writer = csv.DictWriter(fh, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description="File one household's chore photos.")
    ap.add_argument("source", type=Path, help="folder of photographs to import")
    ap.add_argument("--household", required=True, help="anonymous id, e.g. H03")
    ap.add_argument("--chore", required=True, choices=CHORES)
    ap.add_argument("--state", required=True, choices=STATES)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    household = args.household.strip().upper()
    if not (len(household) >= 2 and household[0] == "H" and household[1:].isdigit()):
        return fail(f"--household should look like H01, got {household!r}")

    if not args.source.is_dir():
        return fail(f"{args.source} is not a folder")

    photos = sorted(p for p in args.source.iterdir() if p.suffix.lower() in SUFFIXES)
    if not photos:
        return fail(f"no images found in {args.source}")

    rows = load_manifest()
    seen_hashes = {r["file_sha256"] for r in rows}

    target = RAW / household / args.chore / args.state
    existing = len(list(target.glob("*.jpg"))) if target.exists() else 0

    print(f"{len(photos)} image(s) -> {target.relative_to(ROOT)}")
    if existing:
        print(f"  ({existing} already filed here; numbering continues)")

    added, skipped = 0, 0

    for photo in photos:
        try:
            img = Image.open(photo)
            img.load()
        except Exception as exc:
            print(f"  skip {photo.name}: cannot read ({exc})")
            skipped += 1
            continue

        img = img.convert("RGB")
        if max(img.size) > MAX_EDGE:
            scale = MAX_EDGE / max(img.size)
            img = img.resize(
                (round(img.width * scale), round(img.height * scale)),
                Image.Resampling.LANCZOS,
            )

        index = existing + added + 1
        name = f"{household}_{args.chore}_{args.state}_{index:04d}.jpg"
        dest = target / name

        if args.dry_run:
            print(f"  would write {name}")
            added += 1
            continue

        target.mkdir(parents=True, exist_ok=True)

        # Pasted into a fresh image and re-encoded, so nothing from the
        # original info dict -- EXIF, GPS, device id -- can travel with it.
        clean = Image.new("RGB", img.size)
        clean.paste(img)
        clean.save(dest, "JPEG", quality=90)

        digest = hashlib.sha256(dest.read_bytes()).hexdigest()
        if digest in seen_hashes:
            print(f"  skip {photo.name}: identical file already in the dataset")
            dest.unlink()
            skipped += 1
            continue

        seen_hashes.add(digest)
        rows.append({
            "household": household,
            "chore": args.chore,
            "state": args.state,
            "filename": str(dest.relative_to(RAW)).replace("\\", "/"),
            "file_sha256": digest,
            "ahash": average_hash(clean),
            "width": clean.width,
            "height": clean.height,
            "source_name": photo.name,
        })
        added += 1

    if not args.dry_run:
        write_manifest(rows)

    print(f"\nfiled {added}, skipped {skipped}. manifest now holds {len(rows)} image(s).")
    summarise(rows)
    return 0


def summarise(rows: list[dict]) -> None:
    if not rows:
        return
    households = sorted({r["household"] for r in rows})
    print(f"\nhouseholds: {len(households)} ({', '.join(households)})")
    print(f"{'chore':<16}{'state':<10}{'images':>8}")
    for chore in CHORES:
        for state in STATES:
            n = sum(1 for r in rows if r["chore"] == chore and r["state"] == state)
            flag = "" if n >= 300 else "   <- thin"
            print(f"{chore:<16}{state:<10}{n:>8}{flag}")


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
