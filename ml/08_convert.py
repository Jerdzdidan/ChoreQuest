"""M8: the two TFLite files the phone runs, checked against the full model.

    python ml/08_convert.py --dummy            # week one: an untrained model
    python ml/08_convert.py [--install]        # the trained, calibrated model

backbone.tflite: one prepared frame (1, S, S, 3), -1..1, to a 256-number
embedding. MobileNetV2, its pooling and the projection; quantised to int8
with at least --per-class representative frames from every class of the
training split (the input and output stay float, so the app feeds it the
frames it already prepares).

temporal.tflite: the last 16 embeddings, each with its movement energy appended
(1, 16, 257), to one vector: the chore probabilities (calibration temperature
built in), then the activity score, then the scene probabilities. The LSTM
and heads, float16: LSTMs often lose accuracy at int8.

Both are run in the desktop TFLite interpreter and compared with the Keras
model they came from. The script exits with an error if:
- the backbone's embeddings point away from the full model's (mean cosine
  similarity under --min-cosine, 0.98 by default);
- the temporal model's outputs differ by more than --max-difference (0.02);
- in the real run, chore accuracy over validation windows drops by more than
  --max-drop (2 points) from the full model to the two files together.

--dummy does all of this on a model that has never been trained: the ImageNet
MobileNetV2 with a random projection, LSTM and heads, fed random frames. Run it
before any real training: LSTM conversion is the most likely place for a
surprise, and it is better found in week one than week eight. Its files go to
artifacts/dummy/ and are never installed.

The real run writes artifacts/backbone.tflite, temporal.tflite and
model_card.json (classes, scenes, sizes, where each head sits in the output,
the temperature, the version). --install copies the three into
mobile/assets/models/, where the app looks for them (LS-5).
"""
import argparse
import datetime
import json
import shutil

import numpy as np

import pipeline as p


def concrete(model, shape, tf):
    function = tf.function(lambda x: model(x, training=False))
    return function.get_concrete_function(tf.TensorSpec(shape, tf.float32))


def convert_backbone(backbone, size, representative, tf):
    converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete(backbone, [1, size, size, 3], tf)], backbone)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = lambda: ([frame[None].astype(np.float32)] for frame in representative)
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    return converter.convert()


def convert_temporal(temporal, tf):
    converter = tf.lite.TFLiteConverter.from_concrete_functions(
        [concrete(temporal, [1, p.WINDOW, p.EMBED + 1], tf)], temporal)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    return converter.convert()


def cosine(a, b):
    return np.sum(a * b, axis=1) / (np.linalg.norm(a, axis=1) * np.linalg.norm(b, axis=1) + 1e-12)


def representative_frames(per_class, size, rng):
    """Frames from the training split, per_class of each class where it has them."""
    by_class = {}
    for clip in p.clips_in("train"):
        by_class.setdefault(clip["label"], []).append(clip)
    frames = []
    for label, clips in sorted(by_class.items()):
        taken = []
        for i in rng.permutation(len(clips)):
            if len(taken) >= per_class:
                break
            prepared = p.clip_frames(clips[i], size)
            taken += list(prepared[:: max(1, len(prepared) // 8)])
        frames += taken[:per_class]
        if len(taken) < per_class:
            print(f"  only {len(taken)} representative frames for {label}")
    return np.stack(frames)


def validation_windows(size, keys, limit, rng):
    """Up to limit validation clips: their prepared frames, the frames the
    phone would make a signal after, and the label, so the full model and
    the two files see the same pictures."""
    clips = p.clips_in("val")
    out = []
    for i in rng.permutation(len(clips)):
        if len(out) >= limit:
            break
        frames = p.clip_frames(clips[i], size)
        if len(frames) == 0:
            continue
        ends = p.signal_frames(len(frames)) or [len(frames) - 1]
        out.append((frames, ends, keys.index(clips[i]["label"])))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dummy", action="store_true", help="an untrained model and random frames")
    parser.add_argument("--install", action="store_true", help="copy the files into mobile/assets/models/")
    parser.add_argument("--per-class", type=int, default=200)
    parser.add_argument("--check-clips", type=int, default=60, help="validation clips compared end to end")
    parser.add_argument("--min-cosine", type=float, default=0.98)
    parser.add_argument("--max-difference", type=float, default=0.02)
    parser.add_argument("--max-drop", type=float, default=0.02)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    import tensorflow as tf
    from tensorflow import keras

    rng = np.random.default_rng(args.seed)
    manifest = p.load_manifest()
    keys, scenes = p.class_keys(manifest), p.scene_keys(manifest)
    size = p.input_size()

    if args.dummy:
        if args.install:
            p.fail("a dummy model is never installed")
        window = keras.Input((p.WINDOW, p.EMBED + 1))
        lstm = keras.Model(window, list(p.heads(window, len(keys), len(scenes))))
        projection = keras.layers.Dense(p.EMBED)
        projection.build((None, p.POOLED))
        backbone, temporal = p.deploy_models(projection, lstm, size)
        temperature, version, name = 1.0, "dummy", "untrained"
        representative = rng.uniform(-1, 1, (max(args.per_class, 50), size, size, 3)).astype(np.float32)
        check_frames = rng.uniform(-1, 1, (32, size, size, 3)).astype(np.float32)
        out_dir = p.ARTIFACTS / "dummy"
    else:
        p.need_ffmpeg()
        calibration = p.WORK / "calibration.json"
        if calibration.exists():
            with open(calibration, encoding="utf-8") as f:
                saved = json.load(f)
            temperature, version = float(saved["temperature"]), saved["version"]
        else:
            print("No artifacts/work/calibration.json: temperature 1. Run 07_calibrate.py first for a calibrated model.")
            temperature, version = 1.0, "uncalibrated-" + datetime.datetime.now().strftime("%Y%m%d-%H%M")
        name, backbone, temporal, _ = p.deployable(temperature)
        print(f"Converting {name} (temperature {temperature}) at input size {size}.")
        representative = representative_frames(args.per_class, size, rng)
        check_frames = representative[rng.permutation(len(representative))[:64]]
        out_dir = p.ARTIFACTS

    print(f"{len(representative)} representative frames for int8.")
    backbone_lite = convert_backbone(backbone, size, representative, tf)
    temporal_lite = convert_temporal(temporal, tf)
    lite_backbone, lite_temporal = p.Lite(backbone_lite), p.Lite(temporal_lite)

    failures = []
    full_embeddings = backbone.predict(check_frames, verbose=0)
    lite_embeddings = lite_backbone(check_frames)
    similarity = float(np.mean(cosine(full_embeddings, lite_embeddings)))
    print(f"backbone: mean cosine similarity {similarity:.4f} (at least {args.min_cosine})")
    if similarity < args.min_cosine:
        failures.append(f"backbone embeddings moved: cosine {similarity:.4f} < {args.min_cosine}")

    windows = np.stack([
        p.window_at(full_embeddings, p.energies(check_frames), end)
        for end in range(min(len(check_frames), 32))
    ])
    difference = float(np.max(np.abs(temporal.predict(windows, verbose=0) - lite_temporal(windows))))
    print(f"temporal: largest output difference {difference:.4f} (at most {args.max_difference})")
    if difference > args.max_difference:
        failures.append(f"temporal outputs moved: {difference:.4f} > {args.max_difference}")

    layout = p.output_layout(keys, scenes)
    if not args.dummy:
        right_full = right_lite = total = 0
        for frames, ends, label in validation_windows(size, keys, args.check_clips, rng):
            full = backbone.predict(frames, verbose=0)
            lite = lite_backbone(frames)
            energy = p.energies(frames)
            for end in ends:
                a = temporal.predict(p.window_at(full, energy, end)[None], verbose=0)[0]
                b = lite_temporal(p.window_at(lite, energy, end)[None])[0]
                right_full += int(np.argmax(a[: len(keys)]) == label)
                right_lite += int(np.argmax(b[: len(keys)]) == label)
                total += 1
        if total:
            drop = (right_full - right_lite) / total
            print(f"end to end on {total} validation windows: full {right_full / total:.4f}, "
                  f"files {right_lite / total:.4f}, drop {drop:.4f} (at most {args.max_drop})")
            if drop > args.max_drop:
                failures.append(f"accuracy dropped {drop:.4f} > {args.max_drop}")

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "backbone.tflite").write_bytes(backbone_lite)
    (out_dir / "temporal.tflite").write_bytes(temporal_lite)
    card = {
        "version": version,
        "trained_model": name,
        "input_size": size,
        "frames_per_second": p.FPS,
        "window": p.WINDOW,
        "embedding": p.EMBED,
        "classes": keys,
        "other_class": len(keys) - 1,
        "scenes": scenes,
        "outputs": layout,
        "temperature": temperature,
        "movement_energy_grid": p.GRID,
        "converted_at": datetime.datetime.now().isoformat(timespec="seconds"),
    }
    p.write_json(out_dir / "model_card.json", card)
    print(f"Wrote {out_dir.relative_to(p.ML)}/backbone.tflite ({len(backbone_lite) // 1024} KB), "
          f"temporal.tflite ({len(temporal_lite) // 1024} KB) and model_card.json.")

    if failures:
        p.fail("the converted model is not close enough to the full one:\n  " + "\n  ".join(failures))
    if args.install:
        p.APP_MODELS.mkdir(parents=True, exist_ok=True)
        for file in ("backbone.tflite", "temporal.tflite", "model_card.json"):
            shutil.copyfile(out_dir / file, p.APP_MODELS / file)
        print("Installed into mobile/assets/models/. Build the app to ship them.")


if __name__ == "__main__":
    main()
