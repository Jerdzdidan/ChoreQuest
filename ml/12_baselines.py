"""M12 (optional): a ready-made model on the same held-out clips, for comparison.

    python ml/12_baselines.py --movinet movinet_a0_stream.tflite --labels kinetics_600_labels.txt

MoViNet-A0, streaming, as TFLite (download it and the Kinetics-600 label list
yourself, under their licences). It is fed each test clip frame by frame, 5
frames a second at 172 x 172, as it was trained, and asked after every frame.

A chore's probability is the sum of the probabilities of the Kinetics labels
the manifest names for it; "other" is whatever is left. Recognition is then
scored exactly as 09 scores ours, into artifacts/chapter4/baseline_movinet_*.csv,
so the Chapter 4 table can put the two side by side. MoViNet has no activity
head, so its Done timing uses the probability alone (activity counted as 1),
with our thresholds; chores the manifest gives no Kinetics label always score
zero, which is part of the comparison.

Not done here: training our model with and without MoveNet keypoint motion as
an extra input, which needs a second training run of 04 to 06.
"""
import argparse
import importlib

import numpy as np

import pipeline as p

FPS = 5
SIZE = 172


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--movinet", required=True, help="MoViNet-A0 streaming .tflite")
    parser.add_argument("--labels", required=True, help="Kinetics-600 labels, one per line, in output order")
    parser.add_argument("--within", type=float, default=60.0)
    args = parser.parse_args()

    import tensorflow as tf

    p.need_ffmpeg()
    evaluate = importlib.import_module("09_evaluate")
    manifest, config = p.load_manifest(), p.load_config()
    keys, chores = p.class_keys(manifest), p.chore_by_key(manifest)
    with open(args.labels, encoding="utf-8") as f:
        kinetics = [line.strip() for line in f if line.strip()]
    index = {label: i for i, label in enumerate(kinetics)}
    mapping = []
    for key in keys[:-1]:
        labels = [label for source in chores[key].get("sources", []) if source["dataset"] == "kinetics_400"
                  for label in source.get("labels", []) if label in index]
        mapping.append([index[label] for label in labels])
    print(f"{sum(bool(m) for m in mapping)} of {len(mapping)} chores have a Kinetics label MoViNet knows.")

    interpreter = tf.lite.Interpreter(model_path=args.movinet)
    runner = interpreter.get_signature_runner()
    details = runner.get_input_details()
    if "image" not in details:
        p.fail(f"expected an input called image; this model has {sorted(details)}")

    def chore_probabilities(logits):
        e = np.exp(logits - logits.max())
        k = e / e.sum()
        out = np.array([k[m].sum() if m else 0.0 for m in mapping] + [0.0])
        out[-1] = max(0.0, 1.0 - out[:-1].sum())
        return out

    def clip_signals(clip):
        frames = p.decode(p.CLIPS / clip["clip"], FPS)
        states = {name: np.zeros(d["shape"], dtype=d["dtype"]) for name, d in details.items() if name != "image"}
        out = []
        for i, frame in enumerate(frames):
            square = (p.prepare(frame, SIZE) + 1.0) / 2.0
            outputs = runner(**states, image=square[None, None].astype(np.float32))
            logits = outputs.pop("logits")[0]
            states = outputs
            if (i + 1) % FPS == 0:
                out.append((i / FPS, chore_probabilities(logits), 1.0))
        return out

    test = p.clips_in("test")
    truth, probabilities, domains, signals = [], [], [], {}
    for clip in test:
        clip_out = clip_signals(clip)
        if not clip_out:
            continue
        signals[clip["clip"]] = clip_out
        probabilities += [s[1] for s in clip_out]
        truth += [keys.index(clip["label"])] * len(clip_out)
        domains += [clip["domain"]] * len(clip_out)

    original = evaluate.write_csv
    evaluate.write_csv = lambda name, header, rows: original(f"baseline_movinet_{name}", header, rows)
    summary = evaluate.recognition(np.array(truth), np.stack(probabilities), keys, np.array(domains))

    # Done timing over sessions of whole clips, from the signals above.
    own = [c for c in test if c["domain"] == "own" and c["clip"] in signals] or [c for c in test if c["clip"] in signals]
    rows = []
    idle = [p.session_arrays([s for c in group for s in signals[c["clip"]]]) for group in p.sessions(own, "other", 600)]
    for target, key in enumerate(keys[:-1]):
        t = p.thresholds_for(config, key, chores[key].get("min_active_seconds"))
        work = [p.session_arrays([s for c in group for s in signals[c["clip"]]])
                for group in p.sessions(own, key, t["min_seconds"] + args.within + 30)]

        def done(session):
            times, probs, activity = session
            if not len(times):
                return None
            return p.fast_done_time(times, probs[:, target], activity, t["min_probability"], 0.0,
                                    t["min_seconds"], t["gap_seconds"])

        false = sum(done(s) is not None for s in idle)
        times = [done(s) for s in work]
        missed = sum(1 for x in times if x is None or x > t["min_seconds"] + args.within)
        finished = [x for x in times if x is not None]
        rows.append((key, t["min_probability"], t["min_seconds"], len(idle),
                     round(100 * false / len(idle), 1) if idle else "", len(work),
                     round(100 * missed / len(work), 1) if work else "",
                     round(float(np.median(finished)), 1) if finished else ""))
    original("baseline_movinet_done_timing.csv", ["chore", "min_probability", "min_seconds", "idle_sessions",
                                                  "idle_false_trigger_pct", "work_sessions", "work_miss_pct",
                                                  "median_seconds_to_done"], rows)
    for subset, windows, accuracy, macro, ece in summary:
        print(f"  MoViNet-A0 {subset:6} {windows:6} windows  top-1 {accuracy:.4f}  macro-F1 {macro:.4f}  ECE {ece:.4f}")
    print(f"Wrote artifacts/chapter4/baseline_movinet_*.csv.")


if __name__ == "__main__":
    main()
