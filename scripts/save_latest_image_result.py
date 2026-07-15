#!/usr/bin/env python3
"""Save the latest Codex image_generation_call.result PNGs to outputs."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
import zlib


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
BASE64_RE = re.compile(r"^[A-Za-z0-9+/=\s_-]+$")


def default_codex_home() -> Path:
    env_home = os.environ.get("CODEX_HOME")
    if env_home:
        return Path(env_home)
    script_path = Path(__file__).resolve()
    for parent in script_path.parents:
        if (parent / "sessions").is_dir() and (parent / "skills").is_dir():
            return parent
    home_default = Path.home() / ".codex"
    if (home_default / "sessions").is_dir():
        return home_default
    g_default = Path("G:/codex/codex-home")
    if (g_default / "sessions").is_dir():
        return g_default
    return home_default


def iter_rollout_files(sessions_root: Path):
    if not sessions_root.exists():
        return
    for path in sessions_root.rglob("rollout-*.jsonl"):
        if path.is_file():
            yield path


def latest_rollout(sessions_root: Path) -> Path:
    files = list(iter_rollout_files(sessions_root))
    if not files:
        raise FileNotFoundError(f"No rollout JSONL files found under {sessions_root}")
    return max(files, key=lambda p: p.stat().st_mtime)


def walk(value):
    yield value
    if isinstance(value, dict):
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)


def image_call_results(obj):
    for value in walk(obj):
        if not isinstance(value, dict):
            continue
        type_value = str(value.get("type", ""))
        has_result = "result" in value
        if has_result and ("image_generation_call" in type_value or value.get("name") == "image_generation_call"):
            yield value["result"]


def strip_data_url(text: str) -> str:
    text = text.strip()
    if "," in text and text.lower().startswith("data:image/png;base64,"):
        return text.split(",", 1)[1].strip()
    return text


def maybe_decode_png(text: str) -> bytes | None:
    raw = strip_data_url(text)
    if len(raw) < 32 or not BASE64_RE.match(raw):
        return None
    raw = re.sub(r"\s+", "", raw)
    for candidate in (raw, raw.replace("-", "+").replace("_", "/")):
        padded = candidate + "=" * (-len(candidate) % 4)
        try:
            data = base64.b64decode(padded, validate=False)
        except (binascii.Error, ValueError):
            continue
        if data.startswith(PNG_SIGNATURE):
            return data
    return None


def collect_pngs(result):
    pngs = []
    seen = set()
    for value in walk(result):
        if not isinstance(value, str):
            continue
        data = maybe_decode_png(value)
        if data is None:
            continue
        digest = hashlib.sha256(data).hexdigest()
        if digest not in seen:
            seen.add(digest)
            pngs.append(data)
    return pngs


def read_latest_image_results(rollout_path: Path):
    latest_results = []
    with rollout_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            results = list(image_call_results(obj))
            if results:
                latest_results = results
    if not latest_results:
        raise RuntimeError(f"No image_generation_call.result found in {rollout_path}")
    return latest_results


def parse_png(data: bytes):
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("PNG signature mismatch")
    offset = len(PNG_SIGNATURE)
    width = height = None
    saw_ihdr = False
    saw_iend = False
    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_start = offset + 8
        chunk_end = chunk_start + length
        crc_end = chunk_end + 4
        if crc_end > len(data):
            raise ValueError("Truncated PNG chunk")
        chunk_data = data[chunk_start:chunk_end]
        expected_crc = struct.unpack(">I", data[chunk_end:crc_end])[0]
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise ValueError(f"CRC mismatch in {chunk_type.decode('latin1', errors='replace')}")
        if chunk_type == b"IHDR":
            if length != 13:
                raise ValueError("Invalid IHDR length")
            width, height = struct.unpack(">II", chunk_data[:8])
            saw_ihdr = True
        if chunk_type == b"IEND":
            saw_iend = True
            break
        offset = crc_end
    if not saw_ihdr or width is None or height is None:
        raise ValueError("Missing IHDR")
    if width <= 0 or height <= 0:
        raise ValueError("Invalid IHDR dimensions")
    if not saw_iend:
        raise ValueError("Missing IEND")
    return width, height


def safe_prefix(prefix: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", prefix.strip()).strip("-._")
    return cleaned or "generated-image"


def save_pngs(pngs, out_dir: Path, prefix: str):
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = safe_prefix(prefix)
    results = []
    total = len(pngs)
    for index, data in enumerate(pngs, start=1):
        width, height = parse_png(data)
        suffix = f"-{index}" if total > 1 else ""
        path = out_dir / f"{prefix}{suffix}.png"
        counter = 2
        while path.exists():
            path = out_dir / f"{prefix}{suffix}-{counter}.png"
            counter += 1
        path.write_bytes(data)
        written = path.read_bytes()
        read_width, read_height = parse_png(written)
        if (read_width, read_height) != (width, height):
            raise ValueError(f"Readback dimensions changed for {path}")
        results.append(
            {
                "path": str(path.resolve()),
                "png_header": written.startswith(PNG_SIGNATURE),
                "ihdr_width": read_width,
                "ihdr_height": read_height,
                "readable": True,
                "bytes": len(written),
                "sha256": hashlib.sha256(written).hexdigest(),
            }
        )
    return results


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", default=".", help="Current project directory.")
    parser.add_argument("--out-dir", help="Output directory. Defaults to <cwd>/outputs.")
    parser.add_argument("--prefix", default="generated-image", help="Output filename prefix.")
    parser.add_argument("--rollout", help="Specific rollout JSONL path.")
    parser.add_argument("--sessions-root", help="Codex sessions root. Defaults to <CODEX_HOME>/sessions.")
    args = parser.parse_args(argv)

    cwd = Path(args.cwd).resolve()
    out_dir = Path(args.out_dir).resolve() if args.out_dir else cwd / "outputs"
    sessions_root = Path(args.sessions_root).resolve() if args.sessions_root else default_codex_home() / "sessions"
    rollout_path = Path(args.rollout).resolve() if args.rollout else latest_rollout(sessions_root)

    latest_results = read_latest_image_results(rollout_path)
    pngs = []
    for result in latest_results:
        pngs.extend(collect_pngs(result))
    if not pngs:
        raise RuntimeError(f"No Base64 PNG data found in latest image_generation_call.result in {rollout_path}")

    saved = save_pngs(pngs, out_dir, args.prefix)
    print(
        json.dumps(
            {
                "rollout": str(rollout_path),
                "outputs": saved,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)
