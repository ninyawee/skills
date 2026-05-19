#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["google-genai>=1.52.0", "Pillow>=11.0.0"]
# ///
"""
Extract recipe step images from a video using ffmpeg + Gemini smart crop.

Usage:
    # Extract thumbnail + step frames from a video
    recipe-images.py <VIDEO_URL> --output-dir /tmp/recipe-mango/

    # With specific timestamps (seconds)
    recipe-images.py <VIDEO_URL> --timestamps 15 30 45 60 --output-dir /tmp/recipe-mango/

    # Auto-detect key moments (Gemini analyzes video description/transcript for timing)
    recipe-images.py <VIDEO_URL> --auto --output-dir /tmp/recipe-mango/

Workflow:
1. Downloads video via yt-dlp (lowest quality sufficient for frames)
2. Extracts frames at given timestamps via ffmpeg
3. Uses Gemini vision to smart-crop each frame to the subject (food/hands/action)
4. Saves thumbnail.png + step-N.png
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


def run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, timeout=120, **kwargs)


def download_video(url: str, output_path: str) -> str:
    """Download video via yt-dlp, return actual file path."""
    result = run([
        "yt-dlp",
        "-f", "worstvideo[ext=mp4]/worstvideo",
        "-o", output_path,
        url,
    ])
    if result.returncode != 0:
        # Fallback
        result = run(["yt-dlp", "-f", "worst", "-o", output_path, url])
        if result.returncode != 0:
            print(f"Error downloading: {result.stderr}", file=sys.stderr)
            sys.exit(1)

    # Find actual downloaded file (extension may differ)
    parent = Path(output_path).parent
    for f in parent.iterdir():
        if f.name.startswith("video"):
            return str(f)
    return output_path


def extract_frame(video_path: str, timestamp: float, output_path: str) -> bool:
    """Extract a single frame at given timestamp using ffmpeg."""
    result = run([
        "ffmpeg", "-y",
        "-ss", str(timestamp),
        "-i", video_path,
        "-frames:v", "1",
        "-q:v", "2",
        output_path,
    ])
    return result.returncode == 0 and Path(output_path).exists()


def smart_crop(image_path: str, output_path: str, context: str = "") -> bool:
    """Use Gemini to identify subject region, then crop with Pillow."""
    from google import genai
    from google.genai import types

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        # No Gemini key — just center crop to 4:3
        return center_crop(image_path, output_path)

    client = genai.Client(api_key=api_key)

    img = Image.open(image_path)
    w, h = img.size

    # Ask Gemini where the interesting subject is
    img_bytes = Path(image_path).read_bytes()
    mime = "image/jpeg" if image_path.endswith(".jpg") else "image/png"

    prompt = (
        f"This is a frame from a cooking video. {context} "
        f"Image dimensions: {w}x{h} pixels. "
        f"Identify the most important rectangular region showing the food/cooking action. "
        f"Return ONLY a JSON object with the crop coordinates: "
        f'{{"x": <left>, "y": <top>, "w": <width>, "h": <height>}} '
        f"The crop should focus on the subject (food, hands, pot, ingredients) "
        f"and exclude dead space, watermarks, and UI overlays. "
        f"Make the crop roughly 4:3 aspect ratio. "
        f"Return ONLY the JSON, no other text."
    )

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[
                types.Content(parts=[
                    types.Part(inline_data=types.Blob(mime_type=mime, data=img_bytes)),
                    types.Part(text=prompt),
                ])
            ],
        )

        text = response.text.strip()
        # Extract JSON from response (may have markdown code block)
        if "```" in text:
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()

        crop = json.loads(text)
        x, y, cw, ch = int(crop["x"]), int(crop["y"]), int(crop["w"]), int(crop["h"])

        # Clamp to image bounds
        x = max(0, min(x, w - 1))
        y = max(0, min(y, h - 1))
        cw = min(cw, w - x)
        ch = min(ch, h - y)

        if cw < 100 or ch < 100:
            return center_crop(image_path, output_path)

        cropped = img.crop((x, y, x + cw, y + ch))
        cropped.save(output_path, quality=90)
        print(f"    cropped to {cw}x{ch} at ({x},{y})", file=sys.stderr)
        return True

    except Exception as e:
        print(f"    Gemini crop failed ({e}), using center crop", file=sys.stderr)
        return center_crop(image_path, output_path)


def center_crop(image_path: str, output_path: str) -> bool:
    """Simple center crop to 4:3 aspect ratio."""
    img = Image.open(image_path)
    w, h = img.size
    target_ratio = 4 / 3

    current_ratio = w / h
    if current_ratio > target_ratio:
        new_w = int(h * target_ratio)
        left = (w - new_w) // 2
        img = img.crop((left, 0, left + new_w, h))
    elif current_ratio < target_ratio:
        new_h = int(w / target_ratio)
        top = (h - new_h) // 2
        img = img.crop((0, top, w, top + new_h))

    img.save(output_path, quality=90)
    return True


def get_video_duration(video_path: str) -> float:
    """Get video duration in seconds via ffprobe."""
    result = run([
        "ffprobe", "-v", "quiet",
        "-show_entries", "format=duration",
        "-of", "csv=p=0",
        video_path,
    ])
    try:
        return float(result.stdout.strip())
    except ValueError:
        return 0


def auto_timestamps(duration: float, count: int = 6) -> list[float]:
    """Generate evenly-spaced timestamps, skipping intro/outro."""
    if duration <= 0:
        return [5, 15, 30, 45, 60]

    start = min(5, duration * 0.05)  # skip first 5%
    end = duration * 0.90            # skip last 10%
    if end <= start:
        return [duration / 2]

    step = (end - start) / (count - 1) if count > 1 else 0
    return [start + i * step for i in range(count)]


def main():
    parser = argparse.ArgumentParser(description="Extract recipe images from video")
    parser.add_argument("url", help="Video URL")
    parser.add_argument("--timestamps", nargs="+", type=float, help="Timestamps in seconds")
    parser.add_argument("--auto", action="store_true", help="Auto-detect timestamps")
    parser.add_argument("--count", type=int, default=6, help="Number of step images (for --auto)")
    parser.add_argument("--output-dir", default="/tmp/recipe-images", help="Output directory")
    parser.add_argument("--no-crop", action="store_true", help="Skip smart cropping")
    parser.add_argument("--thumbnail-at", type=float, default=None, help="Thumbnail timestamp (default: 33% in)")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        video_path = str(Path(tmpdir) / "video.mp4")

        # Download
        print("Downloading video...", file=sys.stderr)
        actual_path = download_video(args.url, video_path)
        print(f"  saved to {actual_path}", file=sys.stderr)

        # Get duration
        duration = get_video_duration(actual_path)
        print(f"  duration: {duration:.0f}s", file=sys.stderr)

        # Determine timestamps
        if args.timestamps:
            timestamps = args.timestamps
        elif args.auto or not args.timestamps:
            timestamps = auto_timestamps(duration, args.count)
        print(f"  timestamps: {[f'{t:.0f}s' for t in timestamps]}", file=sys.stderr)

        # Extract thumbnail
        thumb_time = args.thumbnail_at if args.thumbnail_at is not None else duration * 0.33
        thumb_raw = str(Path(tmpdir) / "thumb_raw.jpg")
        thumb_out = str(output_dir / "thumbnail.jpg")
        print(f"\nExtracting thumbnail at {thumb_time:.0f}s...", file=sys.stderr)
        if extract_frame(actual_path, thumb_time, thumb_raw):
            if args.no_crop:
                center_crop(thumb_raw, thumb_out)
            else:
                smart_crop(thumb_raw, thumb_out, "This is the thumbnail — crop to show the finished dish or most appetizing shot.")
            print(f"  -> {thumb_out}", file=sys.stderr)

        # Extract step frames
        print(f"\nExtracting {len(timestamps)} step frames...", file=sys.stderr)
        results = []
        for i, ts in enumerate(timestamps, 1):
            raw_path = str(Path(tmpdir) / f"step_{i}_raw.jpg")
            out_path = str(output_dir / f"step-{i}.jpg")

            print(f"  Step {i}: {ts:.0f}s", file=sys.stderr)
            if extract_frame(actual_path, ts, raw_path):
                if args.no_crop:
                    center_crop(raw_path, out_path)
                else:
                    smart_crop(raw_path, out_path, f"Step {i} of a cooking recipe.")
                results.append((i, ts, out_path, True))
                print(f"    -> {out_path}", file=sys.stderr)
            else:
                results.append((i, ts, out_path, False))
                print(f"    FAILED to extract frame", file=sys.stderr)

    # Print markdown summary
    print(f"\n![thumbnail]({thumb_out})\n")
    for i, ts, path, ok in results:
        if ok:
            print(f"### Step {i} ({ts:.0f}s)")
            print(f"![step-{i}]({path})\n")

    succeeded = sum(1 for *_, ok in results if ok)
    print(f"\nDone: thumbnail + {succeeded}/{len(timestamps)} steps in {output_dir}", file=sys.stderr)


if __name__ == "__main__":
    main()
