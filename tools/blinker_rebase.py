#!/usr/bin/env python3
"""Three-way merge Blinker Fluid's Chromium changes onto another revision.

Blinker Fluid (https://github.com/Nodesclock/Blinker-Fluid, GPL-3.0) ships its
port as whole-file replacements for a Chromium M149 checkout. To reuse one of
those changes on a newer Chromium, this script merges, per file:

    ours   = Blinker's file            (Blinker commit, src/<path>)
    base   = upstream at Blinker's base (Chromium 31dce68b / V8 642bb71b / ANGLE a96d1f8d)
    theirs = upstream at the target     (local checkout or a gitiles revision)

with `git merge-file`, then writes the merged file, a diff against the target
(a reference patch, NOT a ready-to-apply series) and a report.

Nothing from Blinker is stored in this repository; it is downloaded on demand.
Stdlib only, so it runs with the python3 that ships with Xcode.

Examples:
  # Against the local checkout (fast; reads target files from disk):
  python3 tools/blinker_rebase.py --target-src ~/chromium/src --categories memory,wasm

  # Without a checkout, against a gitiles revision:
  python3 tools/blinker_rebase.py --target-chromium 3313f82787695ce167d13fb795a435d3019af3f6 \
      --files v8/src/wasm/wasm-js.cc
"""

import argparse
import base64
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

BLINKER_REPO_RAW = "https://raw.githubusercontent.com/Nodesclock/Blinker-Fluid"
GITILES = "https://chromium.googlesource.com"

# Blinker Fluid v.0.3.1 (repo main as of 2026-09-29) and the revisions its
# src/ overlay was made against (BASE_COMMIT.txt / DEPS).
DEFAULT_BLINKER_COMMIT = "c97d6f0ffb56acbbeb89ff529cb7a4f0c77db5bd"
BASE_CHROMIUM = "31dce68b925c2b8efc93df832a86a7c0d03e3fa2"
BASE_V8 = "642bb71b116595bcc50979c0e2d66c06fe0959b5"
BASE_ANGLE = "a96d1f8de35e7a152ea4ab24f1b86c64282d6be7"

REPO_ROOT = Path(__file__).resolve().parent.parent
TRIAGE_TSV = REPO_ROOT / "tools" / "blinker_triage.tsv"
DEFAULT_CATEGORIES = ["core", "memory", "wasm", "jit", "fix"]


def http_get(url, retries=3):
    last_error = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:
                return resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            last_error = e
        except urllib.error.URLError as e:
            last_error = e
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed: {last_error}")


def gitiles_file(repo, rev, path):
    data = http_get(f"{GITILES}/{repo}/+/{rev}/{path}?format=TEXT")
    return None if data is None else base64.b64decode(data)


def split_repo(path, chromium_rev, v8_rev, angle_rev):
    """Maps a Chromium-relative path to (gitiles repo, revision, repo path)."""
    if path.startswith("v8/"):
        return "v8/v8", v8_rev, path[len("v8/"):]
    if path.startswith("third_party/angle/"):
        return "angle/angle", angle_rev, path[len("third_party/angle/"):]
    return "chromium/src", chromium_rev, path


def deps_revision(chromium_rev, name):
    deps = gitiles_file("chromium/src", chromium_rev, "DEPS")
    if deps is None:
        raise RuntimeError(f"DEPS not found at {chromium_rev}")
    m = re.search(r"'%s_revision':\s*'([0-9a-f]{40})'" % name, deps.decode())
    if not m:
        raise RuntimeError(f"{name}_revision not found in DEPS at {chromium_rev}")
    return m.group(1)


def load_triage():
    rows = []
    with open(TRIAGE_TSV, encoding="utf-8") as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            category, path, covered_by, purpose = line.rstrip("\n").split("\t")
            rows.append({"category": category, "path": path,
                         "covered_by": covered_by, "purpose": purpose})
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    target = ap.add_mutually_exclusive_group(required=True)
    target.add_argument("--target-src", type=Path,
                        help="Chromium src/ checkout to merge onto (reads files from disk)")
    target.add_argument("--target-chromium",
                        help="Chromium revision to merge onto (fetched from gitiles)")
    ap.add_argument("--target-v8", help="V8 revision (default: from DEPS of --target-chromium)")
    ap.add_argument("--target-angle", help="ANGLE revision (default: from DEPS of --target-chromium)")
    ap.add_argument("--blinker-commit", default=DEFAULT_BLINKER_COMMIT)
    sel = ap.add_mutually_exclusive_group()
    sel.add_argument("--categories", default=",".join(DEFAULT_CATEGORIES),
                     help="comma-separated triage categories (default: %(default)s)")
    sel.add_argument("--files", help="comma-separated Chromium-relative paths")
    ap.add_argument("--out", type=Path, default=REPO_ROOT / "out" / "blinker-rebase")
    args = ap.parse_args()

    triage = {r["path"]: r for r in load_triage()}
    if args.files:
        paths = [p.strip() for p in args.files.split(",") if p.strip()]
    else:
        wanted = {c.strip() for c in args.categories.split(",")}
        paths = [p for p, r in triage.items() if r["category"] in wanted]
    if not paths:
        sys.exit("no files selected")

    if args.target_chromium:
        v8_rev = args.target_v8 or deps_revision(args.target_chromium, "v8")
        angle_rev = args.target_angle or deps_revision(args.target_chromium, "angle")

    out = args.out
    (out / "merged").mkdir(parents=True, exist_ok=True)
    (out / "diffs").mkdir(parents=True, exist_ok=True)
    results = []

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for path in paths:
            ours = http_get(f"{BLINKER_REPO_RAW}/{args.blinker_commit}/src/{path}")
            repo, rev, rpath = split_repo(path, BASE_CHROMIUM, BASE_V8, BASE_ANGLE)
            base = gitiles_file(repo, rev, rpath)
            if args.target_src:
                tp = args.target_src / path
                theirs = tp.read_bytes() if tp.exists() else None
            else:
                repo, rev, rpath = split_repo(path, args.target_chromium, v8_rev, angle_rev)
                theirs = gitiles_file(repo, rev, rpath)

            row = {"path": path, "category": triage.get(path, {}).get("category", "?")}
            if ours is None:
                row.update(status="blinker-missing", conflicts="")
            elif base is None:
                row.update(status="new-in-blinker", conflicts="")
                dest = out / "merged" / path
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(ours)
            elif theirs is None:
                row.update(status="gone-upstream", conflicts="")
            else:
                for name, data in (("ours", ours), ("base", base), ("theirs", theirs)):
                    (tmp / name).write_bytes(data)
                merged = subprocess.run(
                    ["git", "merge-file", "-p", "-L", "blinker", "-L", "m149", "-L", "target",
                     str(tmp / "ours"), str(tmp / "base"), str(tmp / "theirs")],
                    capture_output=True)
                if merged.returncode < 0:
                    raise RuntimeError(f"git merge-file failed for {path}")
                dest = out / "merged" / path
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(merged.stdout)
                n = merged.returncode
                row.update(status="clean" if n == 0 else "conflict", conflicts=str(n))
                diff = subprocess.run(
                    ["git", "diff", "--no-index", "--no-prefix",
                     str(tmp / "theirs"), str(dest)], capture_output=True)
                text = diff.stdout.decode("utf-8", "replace")
                text = text.replace(str(tmp / "theirs"), "a/" + path).replace(str(dest), "b/" + path)
                (out / "diffs" / (path.replace("/", "__") + ".diff")).write_text(text, encoding="utf-8")
            results.append(row)
            print(f"{row['status']:16} {row['conflicts']:>3}  {path}")

    with open(out / "report.tsv", "w", encoding="utf-8") as f:
        f.write("status\tconflicts\tcategory\tpath\n")
        for r in results:
            f.write(f"{r['status']}\t{r['conflicts']}\t{r['category']}\t{r['path']}\n")
    meta = {"blinker_commit": args.blinker_commit,
            "base": {"chromium": BASE_CHROMIUM, "v8": BASE_V8, "angle": BASE_ANGLE},
            "target": ({"src": str(args.target_src)} if args.target_src else
                       {"chromium": args.target_chromium, "v8": v8_rev, "angle": angle_rev})}
    (out / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(f"\nwrote {out}/merged, {out}/diffs, {out}/report.tsv")
    print("Merged files are reference material: review them, keep only the semantic "
          "change, and turn that into a minimal patch under patches/.")


if __name__ == "__main__":
    main()
