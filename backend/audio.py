from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv", ".wmv", ".mpeg", ".mpg"}
AUDIO_EXTENSIONS = {".mp3", ".m4a", ".wav", ".flac", ".ogg", ".opus", ".aac", ".wma", ".webm"}


def is_video(path: Path) -> bool:
    return path.suffix.lower() in VIDEO_EXTENSIONS


def get_duration(path: Path) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "quiet", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True,
    )
    return float(result.stdout.strip()) if result.returncode == 0 else 0.0


def extract_audio(input_path: Path, output_path: Path | None = None) -> Path:
    if output_path is None:
        output_path = Path(tempfile.mktemp(suffix=".wav"))
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(input_path),
         "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
         str(output_path)],
        capture_output=True, check=True,
    )
    return output_path


def prepare_audio(input_path: Path) -> tuple[Path, bool]:
    """Return (wav_path, is_temp). If input is already WAV 16kHz mono, return as-is."""
    if input_path.suffix.lower() == ".wav":
        return input_path, False
    wav_path = extract_audio(input_path)
    return wav_path, True
