"""M5, stage 1: train the projection, LSTM and heads on the saved features.

    python ml/05_train_head.py [--epochs 60] [--patience 6] [--batch 128]

The CNN stays frozen (04 already ran it). On every window of the training split:

- chore head: every chore plus "other"; label smoothing 0.1, class weights so
  thin chores count as much as common ones;
- activity head: is this task-like movement (1 for a chore clip, 0 for "other");
- scene head: the chore's place on the quest map (kitchen, bedroom, ...), not
  trained on "other" clips, which have no one place.

AdamW at about 1e-3. After each epoch the validation macro-F1 of the chore head
is printed, and training stops when it has not improved for --patience epochs.
The best epoch is kept: artifacts/work/stage1.keras, with artifacts/metrics/
stage1.json (per epoch, then per chore precision, recall and F1) and
stage1_confusion.csv (rows: true chore, columns: predicted).
"""
import argparse
import csv

import numpy as np

import pipeline as p


def class_weights(labels, count):
    seen = np.bincount(labels, minlength=count).astype(np.float64)
    weights = np.where(seen > 0, len(labels) / (count * np.maximum(seen, 1)), 0.0)
    return weights[labels].astype(np.float32)


def batches(windows, classes, batch, shuffle, keras):
    """Windows a batch at a time, with their targets and weights."""
    chore_weight = class_weights(windows.chore, classes)
    activity_weight = class_weights(windows.activity.astype(np.int32), 2)
    scene_weight = (windows.scene >= 0).astype(np.float32)

    class Batches(keras.utils.PyDataset):
        def __init__(self):
            super().__init__()
            self.order = np.arange(len(windows))
            self.on_epoch_end()

        def __len__(self):
            return int(np.ceil(len(windows) / batch))

        def on_epoch_end(self):
            if shuffle:
                np.random.shuffle(self.order)

        def __getitem__(self, i):
            rows = self.order[i * batch:(i + 1) * batch]
            targets = {
                "chore": np.eye(classes, dtype=np.float32)[windows.chore[rows]],
                "activity": windows.activity[rows, None],
                "scene": np.maximum(windows.scene[rows], 0),
            }
            weights = {"chore": chore_weight[rows], "activity": activity_weight[rows], "scene": scene_weight[rows]}
            return windows.inputs(rows), targets, weights

    return Batches()


def predict(model, windows, batch):
    out = []
    for start in range(0, len(windows), batch):
        rows = np.arange(start, min(start + batch, len(windows)))
        out.append(model.predict(windows.inputs(rows), verbose=0)["chore"])
    return np.concatenate(out) if out else np.zeros((0, 0))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--patience", type=int, default=6)
    parser.add_argument("--batch", type=int, default=128)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    args = parser.parse_args()

    from sklearn.metrics import confusion_matrix, f1_score, precision_recall_fscore_support
    from tensorflow import keras

    manifest = p.load_manifest()
    keys, scenes = p.class_keys(manifest), p.scene_keys(manifest)
    clips, splits = p.read_clips(), p.read_splits()
    train = p.FeatureWindows(p.clips_in("train", clips, splits), keys, scenes, manifest)
    val = p.FeatureWindows(p.clips_in("val", clips, splits), keys, scenes, manifest)
    if not len(train) or not len(val):
        p.fail("no training or validation windows; run 03 and 04 first")
    print(f"{len(train)} training windows, {len(val)} validation windows, {len(keys)} classes")

    model = p.stage1_model(len(keys), len(scenes))
    model.compile(
        optimizer=keras.optimizers.AdamW(learning_rate=args.learning_rate, weight_decay=1e-4),
        loss={
            "chore": keras.losses.CategoricalCrossentropy(label_smoothing=0.1),
            "activity": keras.losses.BinaryCrossentropy(),
            "scene": keras.losses.SparseCategoricalCrossentropy(),
        },
    )

    data = batches(train, len(keys), args.batch, True, keras)
    history, best, best_f1, waited = [], None, -1.0, 0
    for epoch in range(1, args.epochs + 1):
        loss = model.fit(data, epochs=1, verbose=0).history["loss"][-1]
        guessed = predict(model, val, args.batch).argmax(axis=1)
        macro = f1_score(val.chore, guessed, labels=range(len(keys)), average="macro", zero_division=0)
        history.append({"epoch": epoch, "loss": round(float(loss), 4), "val_macro_f1": round(float(macro), 4)})
        print(f"epoch {epoch:3}  loss {loss:.4f}  validation macro-F1 {macro:.4f}")
        if macro > best_f1:
            best_f1, best, waited = macro, model.get_weights(), 0
        else:
            waited += 1
            if waited >= args.patience:
                print(f"No better for {args.patience} epochs: stopping.")
                break
    model.set_weights(best)

    p.WORK.mkdir(parents=True, exist_ok=True)
    model.save(p.WORK / "stage1.keras")
    guessed = predict(model, val, args.batch).argmax(axis=1)
    precision, recall, f1, support = precision_recall_fscore_support(
        val.chore, guessed, labels=range(len(keys)), zero_division=0)
    p.write_json(p.METRICS / "stage1.json", {
        "best_val_macro_f1": round(float(best_f1), 4),
        "epochs": history,
        "per_chore": [
            {"chore": key, "precision": round(float(precision[i]), 4), "recall": round(float(recall[i]), 4),
             "f1": round(float(f1[i]), 4), "windows": int(support[i])}
            for i, key in enumerate(keys)
        ],
    })
    matrix = confusion_matrix(val.chore, guessed, labels=range(len(keys)))
    with open(p.METRICS / "stage1_confusion.csv", "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["true \\ predicted", *keys])
        for key, row in zip(keys, matrix):
            writer.writerow([key, *row])
    print(f"Best validation macro-F1 {best_f1:.4f}. Saved artifacts/work/stage1.keras and artifacts/metrics/stage1.*")


if __name__ == "__main__":
    main()
