"""M9: every Chapter 4 table, from the saved models and splits, in one command.

    python ml/09_evaluate.py [--within 60] [--submissions export.tsv]

Runs the two TFLite files the phone ships (artifacts/backbone.tflite and
temporal.tflite, from 08) over the held-out households (the test split), the
way the phone runs them, and writes CSV files to artifacts/chapter4/:

Does it recognise the chore? (every test window; also for your own clips and
the public ones apart)
    recognition_summary.csv     windows, top-1 accuracy, macro-F1, calibration
                                error (ECE, 15 bins)
    recognition_per_chore.csv   precision, recall, F1 and windows per chore
    confusion_matrix.csv        rows: true chore, columns: predicted
    calibration_bins.csv        confidence against accuracy, for the
                                reliability diagram

Does Done appear at the right time? (your own clips: the in-domain ones; the
public ones only if you have none yet, and the file says so)
    done_timing.csv             per chore, at the thresholds the server serves
                                now (backend/resources/model_config.json): how
                                often Done appears during idle or play, how
                                often it fails to appear in real work (not
                                within --within seconds of the chore's
                                minimum), median seconds until Done

Do parents agree? (only with --submissions: the 30 tester families' sessions,
exported from the server's database)
    parent_agreement.csv        per evidence level, sessions approved and
                                turned down, and the turned-down sessions that
                                had Done available (the new "false approval")

    Export it on the server machine with:
    C:\\xampp\\mysql\\bin\\mysql.exe -u root chorequest -B -e "SELECT id,
      verification_mode, model_confidence, active_seconds,
      JSON_UNQUOTE(JSON_EXTRACT(evidence, '$.scene_change')) AS scene_change,
      status FROM submissions WHERE verification_mode IN ('lstm', 'manual')"
      > export.tsv

Is it light enough for a phone? Those numbers come from the phones themselves:
the debug benchmark screen (M11). Is it better than a ready-made model? See
12_baselines.py, which writes the same files for MoViNet.
"""
import argparse
import csv
import json

import numpy as np

import pipeline as p

BINS = 15
IDLE_SESSION = 600


def write_csv(name, header, rows):
    p.CHAPTER4.mkdir(parents=True, exist_ok=True)
    with open(p.CHAPTER4 / name, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def calibration_error(confidence, right):
    edges = np.linspace(0, 1, BINS + 1)
    rows, error = [], 0.0
    for low, high in zip(edges[:-1], edges[1:]):
        inside = (confidence > low) & (confidence <= high)
        if inside.any():
            gap = abs(confidence[inside].mean() - right[inside].mean())
            error += inside.mean() * gap
            rows.append((round(low, 3), round(high, 3), int(inside.sum()),
                         round(float(confidence[inside].mean()), 4), round(float(right[inside].mean()), 4)))
        else:
            rows.append((round(low, 3), round(high, 3), 0, "", ""))
    return float(error), rows


def recognition(truth, probabilities, keys, domains):
    from sklearn.metrics import confusion_matrix, f1_score, precision_recall_fscore_support

    guess = probabilities.argmax(axis=1)
    confidence = probabilities.max(axis=1)
    summary = []
    for subset in ("all", "own", "public"):
        pick = np.ones(len(truth), bool) if subset == "all" else domains == subset
        if not pick.any():
            continue
        ece, _ = calibration_error(confidence[pick], (guess[pick] == truth[pick]).astype(float))
        summary.append((subset, int(pick.sum()), round(float(np.mean(guess[pick] == truth[pick])), 4),
                        round(float(f1_score(truth[pick], guess[pick], labels=range(len(keys)), average="macro",
                                             zero_division=0)), 4), round(ece, 4)))
    write_csv("recognition_summary.csv", ["clips", "windows", "top1_accuracy", "macro_f1", "ece"], summary)

    precision, recall, f1, support = precision_recall_fscore_support(truth, guess, labels=range(len(keys)), zero_division=0)
    write_csv("recognition_per_chore.csv", ["chore", "precision", "recall", "f1", "windows"],
              [(k, round(float(precision[i]), 4), round(float(recall[i]), 4), round(float(f1[i]), 4), int(support[i]))
               for i, k in enumerate(keys)])
    matrix = confusion_matrix(truth, guess, labels=range(len(keys)))
    write_csv("confusion_matrix.csv", ["true \\ predicted", *keys], [(k, *row) for k, row in zip(keys, matrix)])
    _, bins = calibration_error(confidence, (guess == truth).astype(float))
    write_csv("calibration_bins.csv", ["confidence_from", "confidence_to", "windows", "mean_confidence", "accuracy"], bins)
    return summary


def done_timing(test, parts, temporal, keys, chores, config, within):
    own = [c for c in test if c["domain"] == "own"]
    clips, note = (own, "own clips") if own else (test, "public clips: no own clips in the test split yet")

    def arrays(group):
        return [p.session_arrays(p.session_signals([parts[c["clip"]] for c in s if c["clip"] in parts], temporal))
                for s in group]

    idle = [s for s in arrays(p.sessions(clips, "other", IDLE_SESSION)) if len(s[0])]
    rows = []
    for target, key in enumerate(keys[:-1]):
        t = p.thresholds_for(config, key, chores[key].get("min_active_seconds"))
        work = [s for s in arrays(p.sessions(clips, key, t["min_seconds"] + within + 30)) if len(s[0])]

        def done(session):
            times, probabilities, activity = session
            return p.fast_done_time(times, probabilities[:, target], activity, t["min_probability"],
                                    t["min_activity"], t["min_seconds"], t["gap_seconds"])

        false = sum(done(s) is not None for s in idle)
        times = [done(s) for s in work]
        missed = sum(1 for x in times if x is None or x > t["min_seconds"] + within)
        finished = [x for x in times if x is not None]
        rows.append((key, t["min_probability"], t["min_activity"], t["min_seconds"], len(idle),
                     round(100 * false / len(idle), 1) if idle else "", len(work),
                     round(100 * missed / len(work), 1) if work else "",
                     round(float(np.median(finished)), 1) if finished else ""))
    write_csv("done_timing.csv", ["chore", "min_probability", "min_activity", "min_seconds", "idle_sessions",
                                  "idle_false_trigger_pct", "work_sessions", "work_miss_pct",
                                  "median_seconds_to_done"], rows)
    return note


def parent_agreement(path, config):
    with open(path, encoding="utf-8", newline="") as f:
        sample = f.read(2048)
        f.seek(0)
        rows = list(csv.DictReader(f, dialect=csv.Sniffer().sniff(sample, delimiters="\t,")))
    bands = config["evidence_bands"]

    def number(value):
        return None if value in (None, "", "NULL", "null") else float(value)

    def level(row):
        """NotificationController::priorityOf, for a quest session."""
        if row["verification_mode"] == "manual":
            return "manual_check"
        probability, seconds, scene = number(row["model_confidence"]), number(row["active_seconds"]), number(row["scene_change"])
        weak = ((probability or 0.0) < bands["probability"] or (seconds or 0) < bands["active_seconds"]
                or (scene is not None and scene < bands["scene_change"]))
        return "check_carefully" if weak else "looks_genuine"

    decided = [r for r in rows if r["status"] in ("approved", "rejected")]
    out = []
    for name in ("looks_genuine", "check_carefully", "manual_check"):
        these = [r for r in decided if level(r) == name]
        approved = sum(r["status"] == "approved" for r in these)
        out.append((name, len(these), approved, len(these) - approved,
                    round(100 * approved / len(these), 1) if these else ""))
    # Every motion-checked session had Done available: it could not be sent
    # without. A grown-up turning one down is the new false approval.
    motion = [r for r in decided if r["verification_mode"] == "lstm"]
    turned_down = sum(r["status"] == "rejected" for r in motion)
    out.append(("done_available_but_turned_down", len(motion), len(motion) - turned_down, turned_down,
                round(100 * turned_down / len(motion), 1) if motion else ""))
    write_csv("parent_agreement.csv", ["evidence_level", "decided_sessions", "approved", "turned_down", "approved_pct"], out)
    return len(decided)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--within", type=float, default=60.0)
    parser.add_argument("--submissions", help="the server export described above (tab- or comma-separated)")
    parser.add_argument("--models", default=str(p.ARTIFACTS), help="folder with the two .tflite files and model_card.json")
    args = parser.parse_args()

    from pathlib import Path

    folder = Path(args.models)
    for file in ("backbone.tflite", "temporal.tflite", "model_card.json"):
        if not (folder / file).exists():
            p.fail(f"{folder / file} is missing; run 08_convert.py first")
    with open(folder / "model_card.json", encoding="utf-8") as f:
        card = json.load(f)
    manifest, config = p.load_manifest(), p.load_config()
    keys, chores = p.class_keys(manifest), p.chore_by_key(manifest)
    if card["classes"] != keys:
        p.fail("the model's classes differ from the manifest's; convert again (08) after changing the manifest")
    backbone = p.Lite((folder / "backbone.tflite").read_bytes())
    lite_temporal = p.Lite((folder / "temporal.tflite").read_bytes())
    lo, hi = card["outputs"]["chore"]
    activity_at = card["outputs"]["activity"]

    def temporal(windows):
        out = lite_temporal(windows)
        return out[:, lo:hi], out[:, activity_at]

    p.need_ffmpeg()
    test = p.clips_in("test")
    parts, truth, probabilities, domains = {}, [], [], []
    for clip in test:
        frames = p.clip_frames(clip, card["input_size"])
        if not len(frames):
            continue
        embeddings, energy = backbone(frames), p.energies(frames)
        parts[clip["clip"]] = (embeddings, energy)
        ends = p.signal_frames(len(frames)) or [len(frames) - 1]
        chore, _ = temporal(np.stack([p.window_at(embeddings, energy, e) for e in ends]))
        probabilities.append(chore)
        truth += [keys.index(clip["label"])] * len(ends)
        domains += [clip["domain"]] * len(ends)
    if not probabilities:
        p.fail("no test clips could be read")

    summary = recognition(np.array(truth), np.concatenate(probabilities), keys, np.array(domains))
    note = done_timing(test, parts, temporal, keys, chores, config, args.within)
    print(f"Model {card['version']} on {len(parts)} held-out clips.")
    for subset, windows, accuracy, macro, ece in summary:
        print(f"  {subset:6} {windows:6} windows  top-1 {accuracy:.4f}  macro-F1 {macro:.4f}  ECE {ece:.4f}")
    print(f"  Done timing from {note}.")
    if args.submissions:
        print(f"  Parent agreement over {parent_agreement(args.submissions, config)} decided sessions.")
    print(f"Wrote the tables to {p.CHAPTER4.relative_to(p.ML)}/.")


if __name__ == "__main__":
    main()
