"""M4: run the frozen MobileNetV2 over every clip, once.

    python ml/04_extract_features.py [--batch 64]

For each clip in data/clips.csv: decode it at 4 frames a second (what the phone
gives the model), prepare each frame exactly as the phone does (pipeline.prepare:
the centre square, nearest-sampled to the model config's input_size, -1..1),
and save data/features/<label>/<clip>.npz with

    pooled  (frames, 1280)  MobileNetV2's pooled features, ImageNet weights
    energy  (frames,)       movement energy per frame (pipeline.movement_energy)

Stage 1 (05) trains the projection, LSTM and heads on these, so the CNN runs
once per frame for the whole dataset instead of once per epoch.

A clip already done is skipped, so the script can be stopped and run again.
Re-run it after changing input_size: the features are only valid for one size,
so the size is stored with them and a mismatch is redone.
"""
import argparse
import time

import numpy as np

import pipeline as p


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--batch", type=int, default=64)
    args = parser.parse_args()

    p.need_ffmpeg()
    size = p.input_size()
    clips = p.read_clips()
    cnn = p.trunk(size)

    done = skipped = failed = 0
    started = time.time()
    for i, clip in enumerate(clips, 1):
        out = p.feature_path(clip)
        if out.exists():
            with np.load(out) as saved:
                if int(saved["size"]) == size:
                    skipped += 1
                    continue
        try:
            frames = p.decode(p.CLIPS / clip["clip"], p.FPS)
        except Exception as e:  # a clip FFmpeg cannot read: say so, carry on
            print(f"  could not read {clip['clip']}: {e}")
            failed += 1
            continue
        if len(frames) == 0:
            failed += 1
            continue
        prepared = np.stack([p.prepare(f, size) for f in frames])
        pooled = cnn.predict(prepared, batch_size=args.batch, verbose=0)
        out.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(out, pooled=pooled.astype(np.float16), energy=p.energies(prepared), size=size, fps=p.FPS)
        done += 1
        if done % 50 == 0:
            rate = done / (time.time() - started)
            print(f"  {i}/{len(clips)} clips, {rate:.1f} a second")

    print(f"Features: {done} new, {skipped} already done, {failed} unreadable, at input size {size}.")


if __name__ == "__main__":
    main()
