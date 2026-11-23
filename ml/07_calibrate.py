"""M7: calibrate the probabilities and pick each chore's thresholds.

    python ml/07_calibrate.py [--idle-rate 0.05] [--within 60] [--dry-run]

Runs the best trained model (06's stage 3, else 2, else 05's stage 1) over the
validation split exactly as the phone will: 4 frames a second, prepared as the
phone prepares them, one signal about every second.

1. Temperature. One number T divides the chore logits so that a probability of
   0.8 means right about 80 percent of the time; T is chosen to minimise the
   validation log-loss. 08 builds it into temporal.tflite.

2. Thresholds. A household's clips of one label are joined into sessions, and
   each session is played through the Done gate (pipeline.DoneGate, the app's
   own rule) for every pair of min_probability and min_activity on a grid:
   - idle false triggers: of the "other" sessions (idle, walking, talking,
     playing, on the phone, up to 10 minutes each), how many would have shown
     Done for this chore. At most --idle-rate (5 percent).
   - work hits: of this chore's sessions, how many showed Done no later than
     --within seconds after a perfect detector could have (the chore's minimum
     seconds of movement). The pair with the most hits among those under the
     idle rate is chosen; a chore with no pair under it gets the strictest
     pair, and is marked, as is one that still misses more than 10 percent
     of real work: the plan asks for both at once.
   min_seconds stays as the catalogue sets it; gap_seconds as the defaults do.

The expected idle false-trigger rate and work miss rate at the chosen
thresholds are printed per chore, then written to backend/resources/
model_config.json (BE-6: phones read it at their next app open, no new APK)
with a new version, and to artifacts/work/calibration.json for 08.
--dry-run prints the table and writes nothing.
"""
import argparse
import datetime

import numpy as np

import pipeline as p

PROBABILITIES = np.round(np.arange(0.30, 0.951, 0.05), 2)
ACTIVITIES = np.round(np.arange(0.10, 0.801, 0.10), 2)
IDLE_SESSION = 600  # seconds: the longest an alarm rings
WORK_TARGET = 0.90  # the plan's target: Done in at least 90 percent of real work


def softmax(logits, temperature):
    z = logits / temperature
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def fit_temperature(logits, labels):
    best, best_loss = 1.0, np.inf
    for t in np.arange(0.5, 5.001, 0.01):
        probabilities = softmax(logits, t)
        loss = -np.mean(np.log(probabilities[np.arange(len(labels)), labels] + 1e-12))
        if loss < best_loss:
            best, best_loss = float(t), loss
    return round(best, 2), float(best_loss)


def rates(target, positive, negative, gate_settings, within):
    """Idle false-trigger rate, work hit rate and median seconds to Done for
    one pair of thresholds, over sessions (as pipeline.session_arrays)."""
    min_probability, min_activity, min_seconds, gap = gate_settings

    def done(session):
        times, probabilities, activity = session
        return p.fast_done_time(times, probabilities[:, target], activity, min_probability, min_activity, min_seconds, gap)

    triggered = sum(done(s) is not None for s in negative)
    times = [done(s) for s in positive]
    hits = [t for t in times if t is not None and t <= min_seconds + within]
    finished = [t for t in times if t is not None]
    return (
        triggered / len(negative) if negative else None,
        len(hits) / len(positive) if positive else None,
        float(np.median(finished)) if finished else None,
    )


def choose(target, positive, negative, min_seconds, gap, idle_rate, within):
    """The pair with the most work hits among those under the idle rate."""
    best, fallback = None, None
    for probability in PROBABILITIES:
        for activity in ACTIVITIES:
            idle, hit, median = rates(target, positive, negative, (probability, activity, min_seconds, gap), within)
            row = (float(probability), float(activity), idle, hit, median)
            safe = idle is None or idle <= idle_rate
            # On a tie, the later, stricter pair.
            if safe and (best is None or (hit or 0) >= (best[3] or 0)):
                best = row
            if fallback is None or (idle or 0) < (fallback[2] or 0) or (
                    (idle or 0) == (fallback[2] or 0) and (hit or 0) > (fallback[3] or 0)):
                fallback = row
    return (best, True) if best else (fallback, False)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--idle-rate", type=float, default=0.05)
    parser.add_argument("--within", type=float, default=60.0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    p.need_ffmpeg()
    manifest = p.load_manifest()
    keys = p.class_keys(manifest)
    chores = p.chore_by_key(manifest)
    config = p.load_config()
    size = p.input_size(config)
    name, backbone, _, lstm = p.deployable()
    print(f"Calibrating {name} on the validation split, input size {size}.")

    val = p.clips_in("val")
    parts = {}
    for clip in val:
        frames = p.clip_frames(clip, size)
        if len(frames):
            parts[clip["clip"]] = (backbone.predict(frames, verbose=0), p.energies(frames))

    def raw(windows):
        logits, activity, _ = lstm.predict(windows, verbose=0)
        return logits, activity[:, 0]

    # 1. Temperature, on every validation window.
    window_logits, window_labels = [], []
    for clip in val:
        if clip["clip"] in parts:
            embeddings, energy = parts[clip["clip"]]
            ends = p.signal_frames(len(embeddings)) or [len(embeddings) - 1]
            logits, _ = raw(np.stack([p.window_at(embeddings, energy, e) for e in ends]))
            window_logits.append(logits)
            window_labels += [keys.index(clip["label"])] * len(ends)
    if not window_logits:
        p.fail("no validation clips could be read")
    temperature, loss = fit_temperature(np.concatenate(window_logits), np.array(window_labels))
    print(f"Temperature {temperature} (validation log-loss {loss:.4f}).")

    def temporal(windows):
        logits, activity = raw(windows)
        return softmax(logits, temperature), activity

    def signals_of(group):
        return [p.session_arrays(p.session_signals([parts[c["clip"]] for c in session if c["clip"] in parts], temporal))
                for session in group]

    # 2. Thresholds, per chore.
    negative = [s for s in signals_of(p.sessions(val, "other", IDLE_SESSION)) if len(s[0])]
    chosen, table = {}, []
    for target, key in enumerate(keys[:-1]):
        settings = p.thresholds_for(config, key, chores[key].get("min_active_seconds"))
        min_seconds, gap = settings["min_seconds"], settings["gap_seconds"]
        positive = [s for s in signals_of(p.sessions(val, key, min_seconds + args.within + 30)) if len(s[0])]
        if not positive or not negative:
            table.append((key, None, None, None, None, None, len(positive), len(negative), "no sessions: defaults kept"))
            continue
        (probability, activity, idle, hit, median), safe = choose(
            target, positive, negative, min_seconds, gap, args.idle_rate, args.within)
        chosen[key] = {"min_probability": probability, "min_activity": activity}
        notes = [] if safe else [f"over {args.idle_rate:.0%} idle at every setting"]
        if hit is not None and hit < WORK_TARGET:
            notes.append(f"misses over {1 - WORK_TARGET:.0%} of real work")
        table.append((key, probability, activity, idle, hit, median, len(positive), len(negative), "; ".join(notes)))

    print(f"\n{'chore':30} {'prob':>5} {'act':>5} {'idle':>6} {'miss':>6} {'median':>7} {'work':>5} {'idle':>5}")
    print(f"{'':30} {'':>5} {'':>5} {'Done%':>6} {'%':>6} {'s':>7} {'sess':>5} {'sess':>5}")
    for key, probability, activity, idle, hit, median, n_pos, n_neg, note in table:
        def pct(x):
            return "-" if x is None else f"{100 * x:.1f}"
        miss = None if hit is None else 1 - hit
        print(f"{key:30} {probability if probability is not None else '-':>5} {activity if activity is not None else '-':>5} "
              f"{pct(idle):>6} {pct(miss):>6} {median if median is not None else '-':>7} {n_pos:>5} {n_neg:>5}  {note}")

    if args.dry_run:
        print("\nDry run: nothing written.")
        return
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    config["version"] = f"calibrated-{stamp}"
    config["model"]["temperature"] = temperature
    config["chores"] = {**(config.get("chores") or {}), **chosen}
    p.write_json(p.MODEL_CONFIG, config)
    p.write_json(p.WORK / "calibration.json", {
        "model": name, "temperature": temperature, "version": config["version"],
        "idle_rate": args.idle_rate, "within": args.within,
        "chores": {row[0]: {"min_probability": row[1], "min_activity": row[2], "idle_false_trigger": row[3],
                            "work_hit": row[4], "median_seconds_to_done": row[5], "work_sessions": row[6],
                            "idle_sessions": row[7], "note": row[8]} for row in table},
    })
    print(f"\nWrote backend/resources/model_config.json (version {config['version']}) and artifacts/work/calibration.json.")


if __name__ == "__main__":
    main()
