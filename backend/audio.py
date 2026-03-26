from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv", ".wmv", ".mpeg", ".mpg"}
AUDIO_EXTENSIONS = {".mp3", ".m4a", ".wav", ".flac", ".ogg", ".opus", ".aac", ".wma", ".webm"}
# Formats Parakeet/soundfile can load directly without ffmpeg
DIRECT_AUDIO = {".wav", ".flac", ".ogg", ".mp3"}


def is_video(path: Path) -> bool:
    return path.suffix.lower() in VIDEO_EXTENSIONS


def has_ffmpeg() -> bool:
    return shutil.which("ffmpeg") is not None


def get_duration(path: Path) -> float:
    if not shutil.which("ffprobe"):
        return 0.0
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
    """Return (audio_path, is_temp).

    Parakeet's load_audio uses soundfile which handles WAV/FLAC/OGG natively.
    For other formats (M4A, MP4, etc.), convert via ffmpeg if available.
    If ffmpeg isn't available, pass through and let Parakeet try anyway.
    """
    ext = input_path.suffix.lower()

    # WAV and other directly-supported formats — pass through
    if ext in DIRECT_AUDIO:
        return input_path, False

    # Video files or non-direct audio — need ffmpeg
    if has_ffmpeg():
        wav_path = extract_audio(input_path)
        return wav_path, True

    # No ffmpeg — pass through and hope Parakeet can handle it
    return input_path, False
