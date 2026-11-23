"""What the training scripts share, and what must match the phone exactly.

Three things here are copies of the app's own code, kept line for line, because
a model trained on numbers the phone computes differently is a different model:

- prepare(): the picture the CNN sees. The centre square, sampled to
  size x size by nearest pixel, RGB scaled from 0..255 to -1..1.
  (mobile/lib/core/quest_session/frame_prep.dart, prepareYuv)
- movement_energy(): how much the picture changed between two prepared frames,
  the one extra number per frame the LSTM gets.
  (mobile/lib/core/quest_session/lstm_detector.dart, movementEnergy)
- DoneGate: when the Done button appears.
  (mobile/lib/core/quest_session/done_gate.dart)

And one layout both sides read from backend/resources/model_config.json:
backbone.tflite takes one prepared frame (1, S, S, 3) and gives a 256-number
embedding; temporal.tflite takes the last 16 of them, each with its movement
energy appended (1, 16, 257), and gives one vector: the chore probabilities
(every chore plus "other"), then the activity score, then the scene
probabilities.

TensorFlow is imported only inside the functions that need it, so the parts that
are plain arithmetic run, and can be checked, on a machine without it.
"""
import csv
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

ML = Path(__file__).resolve().parent
ROOT = ML.parent

# Never committed (see .gitignore): videos, clips, frames and features.
DATA = ML / "data"
RAW = DATA / "raw"
CLIPS = DATA / "clips"
FRAMES = DATA / "frames"
FEATURES = DATA / "features"
CLIPS_CSV = DATA / "clips.csv"
SPLITS_JSON = DATA / "splits.json"

# Trained Keras models (*.keras is git-ignored), metrics and the shipped files.
ARTIFACTS = ML / "artifacts"
WORK = ARTIFACTS / "work"
METRICS = ARTIFACTS / "metrics"
CHAPTER4 = ARTIFACTS / "chapter4"

MANIFEST = ML / "chore_manifest.json"
MODEL_CONFIG = ROOT / "backend" / "resources" / "model_config.json"
APP_MODELS = ROOT / "mobile" / "assets" / "models"

CLIP_FPS = 8   # clips are cut at this rate, so training can vary the speed
FPS = 4        # what the phone gives the model
WINDOW = 16    # frames the LSTM looks at: four seconds
POOLED = 1280  # MobileNetV2's pooled features
EMBED = 256    # the projection the backbone ends with
GRID = 16      # movement energy is sampled on a 16 x 16 grid
SHORT_SIDE = 256  # clips and cached frames are this tall (or wide), no more
CLIP_COLUMNS = ["clip", "source", "household", "start", "end", "label", "domain"]


def fail(message):
    sys.exit(f"error: {message}")


# ---------------------------------------------------------------- the manifest

def load_manifest():
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def class_keys(manifest):
    """Chore keys by model class, then "other" last, as the model's outputs."""
    lstm = sorted((c for c in manifest["chores"] if c["verification_mode"] == "lstm"), key=lambda c: c["model_class"])
    keys = [c["key"] for c in lstm]
    if [c["model_class"] for c in lstm] != list(range(len(keys))) or manifest["other_class"] != len(keys):
        fail("model classes must run 0..n-1 with other_class = n; run check_manifest.py")
    return keys + ["other"]


def scene_keys(manifest):
    """The scene head's classes: the quest map's places."""
    return sorted({c["location"] for c in manifest["chores"]})


def chore_by_key(manifest):
    return {c["key"]: c for c in manifest["chores"]}


# ---------------------------------------------------------------- the model config

def load_config():
    with open(MODEL_CONFIG, encoding="utf-8") as f:
        return json.load(f)


def input_size(config=None):
    return int((config or load_config())["model"]["input_size"])


# ---------------------------------------------------------------- copied from the phone

def prepare(frame, size):
    """An RGB frame (H x W x 3, uint8) as the CNN takes it: the centre square,
    nearest-sampled to size x size, scaled to -1..1. As prepareYuv does."""
    height, width = frame.shape[:2]
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    points = (np.arange(size) * side) // size
    square = frame[top + points][:, left + points]
    return square.astype(np.float32) / 127.5 - 1.0


def movement_energy(previous, current):
    """How much the picture changed between two prepared frames, 0 to 1: the
    mean absolute change in brightness over a 16 x 16 grid of points. The
    first frame of a session has none."""
    if previous is None:
        return 0.0
    size = current.shape[0]
    points = (np.arange(GRID) * size) // GRID
    weights = np.array([0.299, 0.587, 0.114], dtype=np.float32)
    before = previous[points][:, points] @ weights
    after = current[points][:, points] @ weights
    return float(np.mean(np.abs(after - before)) / 2.0)


def energies(prepared):
    """Movement energy for every frame of a sequence."""
    out = np.zeros(len(prepared), dtype=np.float32)
    for i in range(1, len(prepared)):
        out[i] = movement_energy(prepared[i - 1], prepared[i])
    return out


def window_at(embeddings, energy, end):
    """The LSTM's input for the frame at index end: the last WINDOW frames up
    to it, the earliest repeated at the front when there are fewer, as the
    phone does at the start of a session."""
    start = end - WINDOW + 1
    rows = [max(i, 0) for i in range(start, end + 1)]
    return np.concatenate([embeddings[rows], energy[rows, None]], axis=1)


def signal_frames(count):
    """Which frames the phone runs the LSTM after: every FPS-th, about once a
    second, starting with the FPS-th."""
    return list(range(FPS - 1, count, FPS))


class DoneGate:
    """When Done appears. done_gate.dart, line for line."""

    def __init__(self, min_probability, min_activity, min_seconds, gap_seconds):
        self.min_probability = min_probability
        self.min_activity = min_activity
        self.min_seconds = min_seconds
        self.gap_seconds = gap_seconds
        self.first_movement = None
        self.last_match = None
        self.done_at = None
        self.active_seconds = 0.0

    def matches(self, probability, activity):
        return probability >= self.min_probability and activity >= self.min_activity

    def feed(self, at, probability, activity):
        """One signal, at seconds into the session. Returns the time Done
        became available, if this signal made it so."""
        if not self.matches(probability, activity):
            return None
        if self.first_movement is None:
            self.first_movement = at
        if self.last_match is not None:
            gap = at - self.last_match
            if 0 <= gap <= self.gap_seconds:
                self.active_seconds += gap
        self.last_match = at
        if self.done_at is None and self.active_seconds >= self.min_seconds:
            self.done_at = at
            return at
        return None


def thresholds_for(config, chore_key, catalogue_min_seconds):
    """ModelConfig.thresholdsFor in the app."""
    chores = config.get("chores")
    entry = chores.get(chore_key, {}) if isinstance(chores, dict) else {}
    defaults = config.get("defaults", {})

    def pick(key, fallback):
        return entry.get(key, defaults.get(key, fallback))

    min_seconds = entry.get("min_seconds", catalogue_min_seconds if catalogue_min_seconds is not None else defaults.get("min_seconds", 30))
    return {
        "min_probability": float(pick("min_probability", 0.6)),
        "min_activity": float(pick("min_activity", 0.3)),
        "min_seconds": int(min_seconds),
        "gap_seconds": int(pick("gap_seconds", 8)),
    }


def done_time(signals, target, gate):
    """When Done appeared in a session, from its signals (seconds, chore
    probabilities, activity), for the chore at index target; None if never."""
    for at, probabilities, activity in signals:
        when = gate.feed(at, float(probabilities[target]), float(activity))
        if when is not None:
            return when
    return None


# ---------------------------------------------------------------- clips and splits

def read_clips():
    if not CLIPS_CSV.exists():
        fail(f"{CLIPS_CSV} is missing; run 02_extract_clips.py first")
    with open(CLIPS_CSV, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def read_splits():
    if not SPLITS_JSON.exists():
        fail(f"{SPLITS_JSON} is missing; run 03_make_splits.py first")
    with open(SPLITS_JSON, encoding="utf-8") as f:
        return json.load(f)


def clips_in(split, clips=None, splits=None):
    """The clips whose household is in this split."""
    clips = clips if clips is not None else read_clips()
    households = set((splits or read_splits())[split])
    return [c for c in clips if c["household"] in households]


def feature_path(clip):
    return FEATURES / (Path(clip["clip"]).with_suffix(".npz"))


def frames_path(clip):
    return FRAMES / (Path(clip["clip"]).with_suffix(".npy"))


# ---------------------------------------------------------------- video

def need_ffmpeg():
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            fail(f"{tool} is not on PATH. Install FFmpeg (https://ffmpeg.org) and try again.")


def video_size(path):
    """Width and height of a clip this pipeline cut (no rotation flag left)."""
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    width, height = (int(v) for v in out.split(",")[:2])
    return width, height


def video_seconds(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return float(out)


def decode(path, fps):
    """Every frame of a cut clip at fps, as uint8 RGB (T, H, W, 3)."""
    width, height = video_size(path)
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"fps={fps}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True,
    ).stdout
    frame = width * height * 3
    count = len(raw) // frame
    return np.frombuffer(raw[: count * frame], dtype=np.uint8).reshape(count, height, width, 3)


# ---------------------------------------------------------------- the network

def heads(x, classes, scenes):
    """The LSTM and its three heads, from (16, 257) inputs. The chore head
    gives logits; softmax (and the calibration temperature) come after."""
    from tensorflow import keras

    x = keras.layers.LSTM(128, name="lstm")(x)
    x = keras.layers.Dropout(0.3, name="dropout")(x)
    chore = keras.layers.Dense(classes, name="chore_logits")(x)
    activity = keras.layers.Dense(1, activation="sigmoid", name="activity")(x)
    scene = keras.layers.Dense(scenes, activation="softmax", name="scene")(x)
    return chore, activity, scene


def stage1_model(classes, scenes):
    """Trained on saved features: per frame the pooled CNN features and the
    movement energy, the projection to 256 applied to every frame, then the
    LSTM and heads."""
    from tensorflow import keras

    pooled = keras.Input((WINDOW, POOLED), name="pooled")
    energy = keras.Input((WINDOW, 1), name="energy")
    projected = keras.layers.TimeDistributed(keras.layers.Dense(EMBED, name="projection"), name="project")(pooled)
    chore, activity, scene = heads(keras.layers.Concatenate(name="with_energy")([projected, energy]), classes, scenes)
    chore = keras.layers.Softmax(name="chore")(chore)
    return keras.Model({"pooled": pooled, "energy": energy}, {"chore": chore, "activity": activity, "scene": scene}, name="stage1")


def trunk(size, weights="imagenet"):
    from tensorflow import keras

    return keras.applications.MobileNetV2(input_shape=(size, size, 3), include_top=False, weights=weights, pooling="avg")


def deploy_models(projection, lstm_heads, size, temperature=1.0, cnn=None):
    """The two files the phone runs. projection: the Dense(256) layer;
    lstm_heads: a model from (16, 257) to (chore logits, activity, scene);
    cnn: a MobileNetV2 trunk (pooled), ImageNet weights when None."""
    from tensorflow import keras

    cnn = cnn or trunk(size)
    frame = keras.Input((size, size, 3), name="frame")
    dense = keras.layers.Dense(EMBED, name="projection")
    embedding = dense(cnn(frame))
    dense.set_weights(projection.get_weights())
    backbone = keras.Model(frame, embedding, name="backbone")

    window = keras.Input((WINDOW, EMBED + 1), name="window")
    logits, activity, scene = lstm_heads(window)
    chore = keras.layers.Softmax(name="chore")(keras.layers.Rescaling(1.0 / temperature, name="temperature")(logits))
    joined = keras.layers.Concatenate(name="outputs")([chore, activity, scene])
    temporal = keras.Model(window, joined, name="temporal")
    return backbone, temporal


def lstm_heads_of(model, classes, scenes):
    """The LSTM and heads of a stage 1 or end-to-end model, as their own model
    from (16, 257)."""
    from tensorflow import keras

    window = keras.Input((WINDOW, EMBED + 1))
    chore, activity, scene = heads(window, classes, scenes)
    out = keras.Model(window, [chore, activity, scene])
    for name in ("lstm", "chore_logits", "activity", "scene"):
        out.get_layer(name).set_weights(model.get_layer(name).get_weights())
    return out


def output_layout(classes, scenes):
    """Where each head sits in temporal.tflite's one output vector."""
    return {
        "chore": [0, len(classes)],
        "activity": len(classes),
        "scene": [len(classes) + 1, len(classes) + 1 + len(scenes)],
    }


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(value, f, indent=2)
        f.write("\n")


# ---------------------------------------------------------------- training windows

class FeatureWindows:
    """Every window the phone would see in a set of clips, from the saved
    features: one ending at each signal frame (about once a second). Kept as
    per-clip arrays plus an index, so the windows themselves are built a batch
    at a time instead of all at once."""

    def __init__(self, clips, keys, scenes, manifest):
        locations = {c["key"]: c["location"] for c in manifest["chores"]}
        self.pooled, self.energy, self.index = [], [], []
        chore, activity, scene, domain = [], [], [], []
        for clip in clips:
            path = feature_path(clip)
            if not path.exists():
                continue
            with np.load(path) as saved:
                pooled, energy = saved["pooled"], saved["energy"]
            if len(pooled) == 0:
                continue
            c = len(self.pooled)
            self.pooled.append(pooled)
            self.energy.append(energy)
            ends = signal_frames(len(pooled)) or [len(pooled) - 1]
            label = clip["label"]
            for end in ends:
                self.index.append((c, end))
                chore.append(keys.index(label))
                activity.append(0.0 if label == "other" else 1.0)
                scene.append(scenes.index(locations[label]) if label in locations else -1)
                domain.append(clip["domain"])
        self.chore = np.array(chore, dtype=np.int32)
        self.activity = np.array(activity, dtype=np.float32)
        self.scene = np.array(scene, dtype=np.int32)
        self.domain = np.array(domain)

    def __len__(self):
        return len(self.index)

    def inputs(self, rows):
        """Pooled features (n, 16, 1280) and energy (n, 16, 1) for these rows."""
        pooled, energy = [], []
        for row in rows:
            c, end = self.index[row]
            window = window_at(self.pooled[c].astype(np.float32), self.energy[c], end)
            pooled.append(window[:, :POOLED])
            energy.append(window[:, POOLED:])
        return {"pooled": np.stack(pooled), "energy": np.stack(energy)}


# ---------------------------------------------------------------- sessions, as the phone runs them

def clip_frames(clip, size):
    """A clip as the phone would feed it: 4 frames a second, prepared."""
    frames = decode(CLIPS / clip["clip"], FPS)
    return np.stack([prepare(f, size) for f in frames]) if len(frames) else np.zeros((0, size, size, 3), np.float32)


def sessions(clips, label, longest):
    """A household's clips of one label, joined end to end into sessions of
    up to `longest` seconds: public clips are a few seconds each, and a quest
    session lasts minutes."""
    by_home = {}
    for clip in clips:
        if clip["label"] == label:
            by_home.setdefault(clip["household"], []).append(clip)
    out = []
    for home in sorted(by_home):
        current, length = [], 0.0
        for clip in by_home[home]:
            current.append(clip)
            length += clip_seconds(clip)
            if length >= longest:
                out.append(current)
                current, length = [], 0.0
        if current:
            out.append(current)
    return out


def clip_seconds(clip):
    return float(clip["end"]) - float(clip["start"])


def session_signals(parts, temporal):
    """The signals a phone would make over a session, from each clip's frame
    embeddings and movement energy (joined in order), and temporal: a function
    from windows (n, 16, 257) to (chore probabilities (n, classes), activity
    (n,)). One signal every FPS frames: (seconds, probabilities, activity)."""
    if not parts:
        return []
    embeddings = np.concatenate([e for e, _ in parts])
    energy = np.concatenate([g for _, g in parts])
    ends = signal_frames(len(embeddings))
    if not ends:
        return []
    probabilities, activity = temporal(np.stack([window_at(embeddings, energy, end) for end in ends]))
    return [(end / FPS, probabilities[i], float(activity[i])) for i, end in enumerate(ends)]


# ---------------------------------------------------------------- the trained model, as the phone will run it

def trained_model():
    """The best model trained so far: stage 3, else 2, else 1."""
    from tensorflow import keras

    for name in ("stage3", "stage2", "stage1"):
        path = WORK / f"{name}.keras"
        if path.exists():
            return name, keras.models.load_model(path)
    fail("no trained model in artifacts/work/; run 05_train_head.py (and 06) first")


def deployable(temperature=1.0):
    """The trained model split as the phone runs it: backbone (frame to
    embedding) and temporal (window to one output vector), plus the LSTM and
    heads alone, giving chore logits, for calibration."""
    manifest = load_manifest()
    keys, scenes, size = class_keys(manifest), scene_keys(manifest), input_size()
    name, model = trained_model()
    cnn = trunk(size) if name == "stage1" else model.get_layer("cnn").layer
    projection = model.get_layer("project").layer
    lstm = lstm_heads_of(model, len(keys), len(scenes))
    backbone, temporal = deploy_models(projection, lstm, size, temperature, cnn)
    return name, backbone, temporal, lstm


def session_arrays(signals):
    """A session's signals as arrays: times (n,), probabilities (n, classes),
    activity (n,)."""
    if not signals:
        return np.zeros(0), np.zeros((0, 0)), np.zeros(0)
    return (np.array([s[0] for s in signals], dtype=np.float64), np.stack([s[1] for s in signals]),
            np.array([s[2] for s in signals], dtype=np.float64))


def fast_done_time(times, probability, activity, min_probability, min_activity, min_seconds, gap_seconds):
    """DoneGate over a whole session at once, for one chore's probabilities:
    the same answer, without a Python loop per signal."""
    matched = times[(probability >= min_probability) & (activity >= min_activity)]
    if len(matched) == 0:
        return None
    gaps = np.diff(matched)
    active = np.concatenate([[0.0], np.cumsum(np.where((gaps >= 0) & (gaps <= gap_seconds), gaps, 0.0))])
    reached = np.nonzero(active >= min_seconds)[0]
    return float(matched[reached[0]]) if len(reached) else None


class Lite:
    """A TFLite file in the desktop interpreter, fed one input at a time, as
    the phone does."""

    def __init__(self, content):
        import tensorflow as tf

        self.interpreter = tf.lite.Interpreter(model_content=content)
        self.interpreter.allocate_tensors()
        self.input = self.interpreter.get_input_details()[0]["index"]
        self.output = self.interpreter.get_output_details()[0]["index"]

    def __call__(self, batch):
        out = []
        for item in batch:
            self.interpreter.set_tensor(self.input, item[None].astype(np.float32))
            self.interpreter.invoke()
            out.append(self.interpreter.get_tensor(self.output)[0])
        return np.stack(out)
