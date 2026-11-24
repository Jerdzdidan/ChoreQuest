"""DS-3: mark where each chore happens in the shortlisted HomER v2 videos.

    python ml/10_label_homer.py            # then open http://127.0.0.1:8765
    python ml/10_label_homer.py --port 8770

A small page in your browser, served from this machine only: it plays one
shortlisted video at a time (streamed from HomER's link; nothing is
downloaded), and you mark each stretch where a chore is being done.

  Space   play or pause            S  the chore starts here
  Left    back 5 seconds           E  the chore ends here
  Right   forward 5 seconds        A  add the marked stretch

Mark "other" for stretches where the person is plainly not doing any chore
(walking, talking, idle): the model needs those too. A video with no chore in
it is marked "No chore here" and not shown again.

HomER has no participant ids, but 420 people recorded its 765 videos, so some
recorded several. If you recognise someone from another video (the same
hands, room or sink), give both videos the same name in "Recorded by": the
split (03) then keeps that person's videos on one side, so no one is in both
training and test. Left alone, each video counts as its own person.

Every save writes labels/homer_v2/segments.csv (video_id, start, end,
chore_key, seconds into the video) and labels/homer_v2/videos.csv (video_id,
person, status). Keep both with the team's data, not in the repository.
"""
import argparse
import json
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pipeline as p

SHORTLIST_COLUMNS = ["video_id", "category", "chores", "duration_sec", "size_mb", "description"]
STATUSES = {"done", "skipped"}


def state():
    """Everything the page shows: the chores to choose from, and each
    shortlisted video with its link and what has been marked so far."""
    manifest = p.load_manifest()
    chores = [{"key": c["key"], "name": c["name"], "model": c["verification_mode"] == "lstm"} for c in manifest["chores"]]
    links = p.homer_videos()
    segments = p.read_rows(p.HOMER_SEGMENTS, p.SEGMENT_COLUMNS)
    people = {r["video_id"]: r for r in p.read_rows(p.HOMER_PEOPLE, p.PEOPLE_COLUMNS)}
    videos = []
    for row in p.read_rows(p.HOMER_SHORTLIST, SHORTLIST_COLUMNS):
        video_id = str(row["video_id"])
        link = links.get(video_id, {})
        videos.append({
            "video_id": video_id,
            "category": row["category"],
            "suggested": [k for k in row["chores"].split(";") if k],
            "description": row["description"],
            "duration_sec": float(row["duration_sec"] or 0),
            "size_mb": row["size_mb"],
            "preview_url": link.get("preview_url"),
            "download_url": link.get("download_url"),
            "status": (people.get(video_id) or {}).get("status", ""),
            "person": p.homer_person(video_id, people),
            "segments": [
                {"start": float(s["start"]), "end": float(s["end"]), "chore_key": s["chore_key"]}
                for s in segments if str(s["video_id"]) == video_id
            ],
        })
    return {"chores": chores, "videos": videos}


def save(body, known_videos, known_chores):
    """One video's marks, replacing what was saved for it before. Returns a
    problem to show, or None."""
    video_id = str(body.get("video_id", ""))
    if video_id not in known_videos:
        return f"video {video_id!r} is not on the shortlist"
    status = body.get("status")
    if status not in STATUSES:
        return "status must be done or skipped"
    person = " ".join(str(body.get("person") or "").split())[:60]
    duration = known_videos[video_id]
    marks = []
    for segment in body.get("segments") or []:
        try:
            start, end = float(segment["start"]), float(segment["end"])
        except (KeyError, TypeError, ValueError):
            return "each stretch needs a start and an end in seconds"
        key = segment.get("chore_key")
        if key not in known_chores and key != "other":
            return f"{key!r} is not a chore"
        if not 0 <= start < end or (duration and end > duration + 1):
            return f"{start:.1f} to {end:.1f} s is not a stretch of this video"
        marks.append({"video_id": video_id, "start": f"{start:.1f}", "end": f"{end:.1f}", "chore_key": key})
    if status == "done" and not marks:
        return "mark at least one stretch, or choose No chore here"
    if status == "skipped":
        marks = []

    kept = [s for s in p.read_rows(p.HOMER_SEGMENTS, p.SEGMENT_COLUMNS) if str(s["video_id"]) != video_id]
    p.write_rows(p.HOMER_SEGMENTS, p.SEGMENT_COLUMNS, kept + sorted(marks, key=lambda m: float(m["start"])))
    people = [r for r in p.read_rows(p.HOMER_PEOPLE, p.PEOPLE_COLUMNS) if str(r["video_id"]) != video_id]
    people.append({"video_id": video_id, "person": person or f"video-{video_id}", "status": status})
    p.write_rows(p.HOMER_PEOPLE, p.PEOPLE_COLUMNS, sorted(people, key=lambda r: int(r["video_id"])))
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # quiet: the page says what happened
        pass

    def _send(self, status, kind, body):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/":
            self._send(HTTPStatus.OK, "text/html; charset=utf-8", PAGE)
        elif self.path == "/api/state":
            self._send(HTTPStatus.OK, "application/json", json.dumps(state()))
        else:
            self._send(HTTPStatus.NOT_FOUND, "text/plain", "not found")

    def do_POST(self):
        if self.path != "/api/save":
            self._send(HTTPStatus.NOT_FOUND, "text/plain", "not found")
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        except json.JSONDecodeError:
            self._send(HTTPStatus.BAD_REQUEST, "application/json", json.dumps({"error": "not JSON"}))
            return
        shortlist = {str(r["video_id"]): float(r["duration_sec"] or 0)
                     for r in p.read_rows(p.HOMER_SHORTLIST, SHORTLIST_COLUMNS)}
        chores = {c["key"] for c in p.load_manifest()["chores"]}
        problem = save(body, shortlist, chores)
        if problem:
            self._send(HTTPStatus.UNPROCESSABLE_ENTITY, "application/json", json.dumps({"error": problem}))
        else:
            self._send(HTTPStatus.OK, "application/json", json.dumps({"ok": True}))


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>HomER labelling</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{font:15px/1.4 system-ui,sans-serif;margin:0;display:flex;height:100vh;color:#1b1b1b;background:#f6f7f5}
 nav{width:300px;overflow:auto;border-right:1px solid #ccd;background:#fff}
 nav header{padding:10px 12px;position:sticky;top:0;background:#fff;border-bottom:1px solid #dde}
 nav button.item{display:block;width:100%;text-align:left;padding:8px 12px;border:0;border-bottom:1px solid #eee;background:none;cursor:pointer}
 nav button.item.on{background:#e3f0e6}
 .done{color:#1e5e2a}.skipped{color:#888}
 main{flex:1;overflow:auto;padding:14px 18px}
 video{width:100%;max-height:52vh;background:#000;border-radius:8px}
 .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:8px 0}
 button,select,input{font:inherit;padding:6px 10px}
 table{border-collapse:collapse;margin:8px 0}td,th{padding:4px 10px;border-bottom:1px solid #ddd;text-align:left}
 .msg{min-height:1.4em;font-weight:600}.bad{color:#b3261e}.good{color:#1e5e2a}
 kbd{border:1px solid #bbb;border-radius:3px;padding:0 4px;font-size:12px;background:#fff}
</style></head><body>
<nav><header><b>HomER labelling</b><div id="progress"></div>
 <div class="row"><select id="filter"><option value="todo">To do</option><option value="done">Done</option><option value="skipped">No chore</option><option value="all">All</option></select></div></header>
 <div id="list"></div></nav>
<main id="main"><p>Choose a video on the left.</p></main>
<script>
"use strict";
let data = null, current = null, marks = [], startAt = null, endAt = null;
const $ = (id) => document.getElementById(id);
const fmt = (s) => { const m = Math.floor(s / 60), r = (s % 60).toFixed(1).padStart(4, "0"); return m + ":" + r; };
function el(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) { if (k === "on") for (const [ev, fn] of Object.entries(v)) e.addEventListener(ev, fn); else e[k] = v; }
  for (const k of kids) e.append(k);
  return e;
}
async function load() {
  data = await (await fetch("/api/state")).json();
  const done = data.videos.filter(v => v.status === "done"), skipped = data.videos.filter(v => v.status === "skipped");
  const segs = data.videos.reduce((n, v) => n + v.segments.length, 0);
  $("progress").textContent = `${done.length + skipped.length} of ${data.videos.length} videos looked at, ${segs} stretches marked`;
  list();
}
function list() {
  const f = $("filter").value, box = $("list"); box.replaceChildren();
  for (const v of data.videos) {
    const todo = !v.status;
    if (f === "todo" && !todo || f === "done" && v.status !== "done" || f === "skipped" && v.status !== "skipped") continue;
    box.append(el("button", {className: "item" + (current && current.video_id === v.video_id ? " on" : ""), on: {click: () => open(v.video_id)}},
      el("b", {textContent: "#" + v.video_id + " "}), el("span", {className: v.status, textContent: v.status === "done" ? "done" : v.status === "skipped" ? "no chore" : ""}),
      el("div", {textContent: v.category.replaceAll("_", " ") + " · " + fmt(v.duration_sec)}),
      el("div", {textContent: v.suggested.join(", ")})));
  }
}
function chooser(v) {
  const s = el("select", {id: "chore"});
  const named = new Map(data.chores.map(c => [c.key, c]));
  const add = (group, keys) => { const g = el("optgroup", {label: group}); for (const k of keys) g.append(el("option", {value: k, textContent: named.get(k)?.name || k})); s.append(g); };
  add("Suggested by its description", v.suggested);
  add("Every chore", data.chores.map(c => c.key).filter(k => !v.suggested.includes(k)));
  add("Not a chore", ["other"]);
  return s;
}
function open(id) {
  current = data.videos.find(v => v.video_id === id); marks = current.segments.map(s => ({...s})); startAt = endAt = null;
  const v = current, video = el("video", {id: "video", controls: true, preload: "metadata", src: v.preview_url || v.download_url});
  video.addEventListener("error", () => {
    if (video.src !== v.download_url && v.download_url) { video.src = v.download_url; say("The preview would not play; trying the full video.", false); }
    else say("This video will not play. Its link may have expired: run python ml/00_intake.py, then reload.", true);
  });
  $("main").replaceChildren(
    el("h2", {textContent: "#" + v.video_id + " · " + v.category.replaceAll("_", " ")}),
    el("p", {textContent: v.description}), video,
    el("div", {className: "row"}, "Speed ", ...[1, 1.5, 2, 3].map(r => el("button", {textContent: r + "×", on: {click: () => { video.playbackRate = r; }}})),
      el("span", {id: "now"})),
    el("div", {className: "row"}, chooser(v),
      el("button", {textContent: "Starts here (S)", on: {click: markStart}}),
      el("button", {textContent: "Ends here (E)", on: {click: markEnd}}),
      el("span", {id: "pending"}),
      el("button", {textContent: "Add stretch (A)", on: {click: addMark}})),
    el("table", {id: "marks"}),
    el("div", {className: "row"}, "Recorded by ", el("input", {id: "person", value: v.person, size: 24, title: "Same name for videos you recognise as the same person"})),
    el("div", {className: "row"},
      el("button", {textContent: "Save and next", on: {click: () => send("done")}}),
      el("button", {textContent: "No chore here", on: {click: () => send("skipped")}})),
    el("p", {className: "msg", id: "msg"}),
    el("p", {innerHTML: "<kbd>Space</kbd> play or pause · <kbd>←</kbd>/<kbd>→</kbd> 5 seconds · <kbd>S</kbd> start · <kbd>E</kbd> end · <kbd>A</kbd> add"}));
  video.addEventListener("timeupdate", () => { $("now").textContent = fmt(video.currentTime) + " of " + fmt(v.duration_sec); });
  table(); pending(); list();
}
function say(text, bad) { const m = $("msg"); if (m) { m.textContent = text; m.className = "msg " + (bad ? "bad" : "good"); } }
function markStart() { startAt = $("video").currentTime; if (endAt !== null && endAt <= startAt) endAt = null; pending(); }
function markEnd() { endAt = $("video").currentTime; pending(); }
function pending() { $("pending").textContent = (startAt === null ? "–" : fmt(startAt)) + " to " + (endAt === null ? "–" : fmt(endAt)); }
function addMark() {
  if (startAt === null || endAt === null || endAt <= startAt) { say("Mark where the chore starts, then where it ends.", true); return; }
  marks.push({start: +startAt.toFixed(1), end: +endAt.toFixed(1), chore_key: $("chore").value});
  marks.sort((a, b) => a.start - b.start); startAt = endAt = null; pending(); table(); say("Added. Save when the video is done.", false);
}
function table() {
  const named = new Map(data.chores.map(c => [c.key, c.name]));
  $("marks").replaceChildren(el("tr", {}, el("th", {textContent: "From"}), el("th", {textContent: "To"}), el("th", {textContent: "Chore"}), el("th", {})),
    ...marks.map((m, i) => el("tr", {},
      el("td", {}, el("a", {href: "#", textContent: fmt(m.start), on: {click: (e) => { e.preventDefault(); $("video").currentTime = m.start; }}})),
      el("td", {textContent: fmt(m.end)}), el("td", {textContent: m.chore_key === "other" ? "not a chore" : (named.get(m.chore_key) || m.chore_key)}),
      el("td", {}, el("button", {textContent: "Remove", on: {click: () => { marks.splice(i, 1); table(); }}})))));
}
async function send(status) {
  const body = {video_id: current.video_id, status, person: $("person").value, segments: status === "done" ? marks : []};
  const r = await fetch("/api/save", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify(body)});
  const answer = await r.json();
  if (!r.ok) { say(answer.error, true); return; }
  const id = current.video_id; await load();
  const next = data.videos.find(v => !v.status && v.video_id !== id);
  if (next) open(next.video_id); else { open(id); say("Saved. Every shortlisted video has been looked at.", false); }
}
document.addEventListener("keydown", (e) => {
  if (!current || ["INPUT", "SELECT"].includes(e.target.tagName)) return;
  const video = $("video");
  if (e.key === " ") { e.preventDefault(); video.paused ? video.play() : video.pause(); }
  else if (e.key === "ArrowLeft") video.currentTime = Math.max(0, video.currentTime - 5);
  else if (e.key === "ArrowRight") video.currentTime += 5;
  else if (e.key === "s" || e.key === "S") markStart();
  else if (e.key === "e" || e.key === "E") markEnd();
  else if (e.key === "a" || e.key === "A") addMark();
});
$("filter").addEventListener("change", list);
load();
</script></body></html>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-browser", action="store_true", help="do not open the page")
    args = parser.parse_args()
    if not p.HOMER_SHORTLIST.exists():
        p.fail(f"{p.HOMER_SHORTLIST} is missing; run 00_intake.py first")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"Labelling at {url}  (Ctrl+C to stop; every save is written at once)")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
