"""M6, stages 2 and 3: fine-tune the CNN with the LSTM, then adapt to real homes.

    python ml/06_finetune.py [--stage2-epochs 15] [--stage3-epochs 8] [--batch 8]

Starts from stage 1 (05): its projection, LSTM and heads, on a MobileNetV2 with
ImageNet weights. The whole thing now trains end to end on frames:

Stage 2. The last blocks of the CNN (from block 13 on) are unfrozen, BatchNorm
layers stay frozen, and everything trains at about 1e-5, ten to a hundred times
below stage 1, on every training clip. Each training window is augmented the
same way across its 16 frames: a horizontal flip, a random-resized crop (70 to
100 percent of the square), brightness, contrast and colour jitter, a small
rotation; and in time: a random start, speed between 0.8x and 1.25x, and now and
then a dropped frame (the previous one repeated). Movement energy is worked out
from the augmented frames, as the phone would see them.

Stage 3. Training continues with your own propped-phone and CCTV clips (domain
"own" in clips.csv) weighted three times the public ones: the public datasets
are mostly head-mounted cameras, and this stage matters most.

Accuracy on the held-out households (the test split) is reported before and
after stage 3, separately for your own clips and the public ones, so the gain
from your recordings is visible. The best epoch of each stage by validation
macro-F1 is kept: artifacts/work/stage2.keras and stage3.keras, with
artifacts/metrics/stage2.json and stage3.json.

Frames are decoded once into data/frames/ (the centre square, 256 x 256, 8 a
second, about 1.5 MB a second of video) and read from there afterwards.
"""
import argparse

import numpy as np

import pipeline as p

UNFREEZE_FROM = "block_13_expand"
SPEEDS = (0.8, 1.25)
DROP = 0.1
CACHE_SIDE = 256


# ---------------------------------------------------------------- frames

def cached_frames(clip):
    """The clip's frames at 8 a second, centre square, 256 x 256 (uint8)."""
    path = p.frames_path(clip)
    if path.exists():
        return np.load(path, mmap_mode="r")
    frames = p.decode(p.CLIPS / clip["clip"], p.CLIP_FPS)
    squares = np.stack([p.prepare(f, CACHE_SIDE) for f in frames]) if len(frames) else np.zeros((0, CACHE_SIDE, CACHE_SIDE, 3))
    squares = np.round((squares + 1.0) * 127.5).clip(0, 255).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    np.save(path, squares)
    return np.load(path, mmap_mode="r")


def positions(count, rng, augment, end=None):
    """Which cached frames make a 16-frame window at 4 a second. In training,
    a random start, a random speed and the odd dropped frame; otherwise the
    window ending at end, as the phone sees it."""
    step = p.CLIP_FPS / p.FPS
    if augment:
        step *= rng.uniform(*SPEEDS)
        span = step * (p.WINDOW - 1)
        start = rng.uniform(0, max(count - 1 - span, 0))
        out = [min(int(round(start + k * step)), count - 1) for k in range(p.WINDOW)]
        for k in range(1, p.WINDOW):
            if rng.random() < DROP:
                out[k] = out[k - 1]
        return out
    last = end * int(step)
    return [max(last - (p.WINDOW - 1 - k) * int(step), 0) for k in range(p.WINDOW)]


# ---------------------------------------------------------------- augmentation, in TensorFlow

def tf_energy(frames, tf):
    """pipeline.movement_energy over a window of prepared frames (16, S, S, 3)."""
    size = frames.shape[1]
    points = (np.arange(p.GRID) * size) // p.GRID
    grid = tf.gather(tf.gather(frames, points, axis=1), points, axis=2)
    luma = tf.tensordot(grid, tf.constant([0.299, 0.587, 0.114]), axes=1)
    change = tf.reduce_mean(tf.abs(luma[1:] - luma[:-1]), axis=[1, 2]) / 2.0
    return tf.concat([[0.0], change], axis=0)[:, None]


def augment(frames, size, tf):
    """The same flip, crop, colour and rotation for all 16 frames."""
    frames = tf.image.convert_image_dtype(frames, tf.float32)
    if tf.random.uniform(()) < 0.5:
        frames = tf.image.flip_left_right(frames)
    area = tf.random.uniform((), 0.7, 1.0)
    aspect = tf.exp(tf.random.uniform((), np.log(3 / 4), np.log(4 / 3)))
    h = tf.minimum(tf.sqrt(area / aspect), 1.0)
    w = tf.minimum(tf.sqrt(area * aspect), 1.0)
    y0 = tf.random.uniform((), 0.0, 1.0 - h)
    x0 = tf.random.uniform((), 0.0, 1.0 - w)
    box = tf.stack([y0, x0, y0 + h, x0 + w])
    frames = tf.image.crop_and_resize(frames, tf.tile(box[None], [p.WINDOW, 1]), tf.range(p.WINDOW), (size, size))
    angle = tf.random.uniform((), -8.0, 8.0) * np.pi / 180
    cos, sin = tf.cos(angle), tf.sin(angle)
    cx = cy = size / 2
    transform = tf.stack([cos, -sin, cx - cos * cx + sin * cy, sin, cos, cy - sin * cx - cos * cy, 0.0, 0.0])
    frames = tf.raw_ops.ImageProjectiveTransformV3(
        images=frames, transforms=tf.tile(transform[None], [p.WINDOW, 1]), output_shape=[size, size],
        interpolation="BILINEAR", fill_mode="REFLECT", fill_value=0.0)
    frames = tf.image.adjust_brightness(frames, tf.random.uniform((), -0.2, 0.2))
    frames = tf.image.adjust_contrast(frames, tf.random.uniform((), 0.8, 1.2))
    frames = tf.image.adjust_saturation(frames, tf.random.uniform((), 0.8, 1.2))
    return tf.clip_by_value(frames, 0.0, 1.0) * 2.0 - 1.0


def plain(frames, size, tf):
    """As the phone: nearest-sampled to size, -1..1."""
    frames = tf.image.resize(tf.cast(frames, tf.float32), (size, size), method="nearest")
    return frames / 127.5 - 1.0


# ---------------------------------------------------------------- data

def dataset(clips, keys, scenes, manifest, size, batch, training, own_weight, tf, rng):
    locations = {c["key"]: c["location"] for c in manifest["chores"]}
    counts = np.bincount([keys.index(c["label"]) for c in clips], minlength=len(keys)).astype(float)
    class_weight = np.where(counts > 0, len(clips) / (len(keys) * np.maximum(counts, 1)), 0.0)

    def examples():
        order = rng.permutation(len(clips)) if training else range(len(clips))
        for i in order:
            clip = clips[i]
            frames = cached_frames(clip)
            if len(frames) == 0:
                continue
            label = keys.index(clip["label"])
            scene = scenes.index(locations[clip["label"]]) if clip["label"] in locations else -1
            weight = class_weight[label] * (own_weight if clip["domain"] == "own" else 1.0)
            # In training, one random window for every four seconds of clip.
            ends = [None] * max(1, len(frames) // (p.CLIP_FPS * 4)) if training else (p.signal_frames(len(frames) // 2) or [0])
            for end in ends:
                yield (np.asarray(frames[positions(len(frames), rng, training, end)]), label,
                       0.0 if clip["label"] == "other" else 1.0, max(scene, 0), float(weight), float(scene >= 0))

    signature = (
        tf.TensorSpec((p.WINDOW, CACHE_SIDE, CACHE_SIDE, 3), tf.uint8), tf.TensorSpec((), tf.int32),
        tf.TensorSpec((), tf.float32), tf.TensorSpec((), tf.int32), tf.TensorSpec((), tf.float32),
        tf.TensorSpec((), tf.float32),
    )

    def shape(frames, label, activity, scene, weight, scene_weight):
        frames = augment(frames, size, tf) if training else plain(frames, size, tf)
        inputs = {"frames": frames, "energy": tf_energy(frames, tf)}
        targets = {"chore": tf.one_hot(label, len(keys)), "activity": activity[None], "scene": scene}
        weights = {"chore": weight, "activity": weight, "scene": scene_weight}
        return inputs, targets, weights

    data = tf.data.Dataset.from_generator(examples, output_signature=signature)
    return data.map(shape, num_parallel_calls=tf.data.AUTOTUNE).batch(batch).prefetch(tf.data.AUTOTUNE)


# ---------------------------------------------------------------- the model

def end_to_end(stage1, keys, scenes, size, keras):
    frames = keras.Input((p.WINDOW, size, size, 3), name="frames")
    energy = keras.Input((p.WINDOW, 1), name="energy")
    cnn = p.trunk(size)
    x = keras.layers.TimeDistributed(cnn, name="cnn")(frames)
    project = keras.layers.TimeDistributed(keras.layers.Dense(p.EMBED, name="projection"), name="project")
    x = project(x)
    chore, activity, scene = p.heads(keras.layers.Concatenate(name="with_energy")([x, energy]), len(keys), len(scenes))
    model = keras.Model({"frames": frames, "energy": energy},
                        {"chore": keras.layers.Softmax(name="chore")(chore), "activity": activity, "scene": scene})
    project.layer.set_weights(stage1.get_layer("project").layer.get_weights())
    for name in ("lstm", "chore_logits", "activity", "scene"):
        model.get_layer(name).set_weights(stage1.get_layer(name).get_weights())

    cnn.trainable = True
    unfrozen = False
    for layer in cnn.layers:
        unfrozen = unfrozen or layer.name == UNFREEZE_FROM
        layer.trainable = unfrozen and not isinstance(layer, keras.layers.BatchNormalization)
    return model


def compile_model(model, learning_rate, keras):
    model.compile(
        optimizer=keras.optimizers.AdamW(learning_rate=learning_rate, weight_decay=1e-4),
        loss={
            "chore": keras.losses.CategoricalCrossentropy(label_smoothing=0.1),
            "activity": keras.losses.BinaryCrossentropy(),
            "scene": keras.losses.SparseCategoricalCrossentropy(),
        },
    )


def scores(model, data, keys):
    """Window accuracy and macro-F1 of the chore head over a dataset."""
    from sklearn.metrics import f1_score

    truth, guess = [], []
    for inputs, targets, _ in data:
        truth.append(np.argmax(targets["chore"].numpy(), axis=1))
        guess.append(np.argmax(model.predict(inputs, verbose=0)["chore"], axis=1))
    if not truth:
        return {"windows": 0, "accuracy": None, "macro_f1": None}
    truth, guess = np.concatenate(truth), np.concatenate(guess)
    return {
        "windows": int(len(truth)),
        "accuracy": round(float(np.mean(truth == guess)), 4),
        "macro_f1": round(float(f1_score(truth, guess, labels=range(len(keys)), average="macro", zero_division=0)), 4),
    }


def train_stage(name, model, train, val, epochs, keys, keras):
    best, best_f1, history = model.get_weights(), -1.0, []
    for epoch in range(1, epochs + 1):
        loss = model.fit(train, epochs=1, verbose=0).history["loss"][-1]
        result = scores(model, val, keys)
        history.append({"epoch": epoch, "loss": round(float(loss), 4), **{f"val_{k}": v for k, v in result.items()}})
        print(f"{name} epoch {epoch:3}  loss {loss:.4f}  validation macro-F1 {result['macro_f1']}")
        if (result["macro_f1"] or 0) > best_f1:
            best_f1, best = result["macro_f1"] or 0, model.get_weights()
    model.set_weights(best)
    return history


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--stage2-epochs", type=int, default=15)
    parser.add_argument("--stage3-epochs", type=int, default=8)
    parser.add_argument("--batch", type=int, default=8, help="windows a step; each is 16 frames")
    parser.add_argument("--learning-rate", type=float, default=1e-5)
    parser.add_argument("--own-weight", type=float, default=3.0)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    import tensorflow as tf
    from tensorflow import keras

    p.need_ffmpeg()
    stage1_path = p.WORK / "stage1.keras"
    if not stage1_path.exists():
        p.fail("artifacts/work/stage1.keras is missing; run 05_train_head.py first")
    manifest = p.load_manifest()
    keys, scenes, size = p.class_keys(manifest), p.scene_keys(manifest), p.input_size()
    clips, splits = p.read_clips(), p.read_splits()
    rng = np.random.default_rng(args.seed)
    tf.random.set_seed(args.seed)

    def data(split, training, own_weight=1.0, only=None):
        chosen = [c for c in p.clips_in(split, clips, splits) if only is None or c["domain"] == only]
        return dataset(chosen, keys, scenes, manifest, size, args.batch, training, own_weight, tf, rng)

    model = end_to_end(keras.models.load_model(stage1_path), keys, scenes, size, keras)
    compile_model(model, args.learning_rate, keras)

    history2 = train_stage("stage 2", model, data("train", True), data("val", False), args.stage2_epochs, keys, keras)
    model.save(p.WORK / "stage2.keras")
    before = {"own": scores(model, data("test", False, only="own"), keys),
              "public": scores(model, data("test", False, only="public"), keys)}
    p.write_json(p.METRICS / "stage2.json", {"epochs": history2, "test": before})

    if not any(c["domain"] == "own" for c in p.clips_in("train", clips, splits)):
        print("No own clips in the training split: stage 3 skipped. Record them (M10) and run this again.")
        model.save(p.WORK / "stage3.keras")
        return

    compile_model(model, args.learning_rate, keras)
    history3 = train_stage("stage 3", model, data("train", True, own_weight=args.own_weight), data("val", False),
                           args.stage3_epochs, keys, keras)
    model.save(p.WORK / "stage3.keras")
    after = {"own": scores(model, data("test", False, only="own"), keys),
             "public": scores(model, data("test", False, only="public"), keys)}
    p.write_json(p.METRICS / "stage3.json", {"epochs": history3, "test_before": before, "test_after": after})

    print("\nHeld-out households (test split), window accuracy and macro-F1:")
    print(f"{'':8} {'before stage 3':>22} {'after stage 3':>22}")
    for domain in ("own", "public"):
        b, a = before[domain], after[domain]
        print(f"{domain:8} {str(b['accuracy']):>10} {str(b['macro_f1']):>11} {str(a['accuracy']):>10} {str(a['macro_f1']):>11}")


if __name__ == "__main__":
    main()
