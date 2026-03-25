from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Optional

import mlx.core as mx
from parakeet_mlx import AlignedResult, DecodingConfig, Greedy, from_pretrained
from parakeet_mlx.cli import to_srt, to_txt, to_vtt

from backend.audio import get_duration, prepare_audio
from backend.models import OutputFormat, Sentence, TranscribeResult

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "mlx-community/parakeet-tdt-0.6b-v3"
CHUNK_DURATION = 120.0
OVERLAP_DURATION = 15.0


class TranscriptionEngine:
    def __init__(self, model_id: str = DEFAULT_MODEL):
        self._model_id = model_id
        self._model = None

    @property
    def loaded(self) -> bool:
        return self._model is not None

    @property
    def model_name(self) -> str:
        return self._model_id

    def load(self) -> None:
        if self._model is not None:
            return
        logger.info("Loading model: %s", self._model_id)
        self._model = from_pretrained(self._model_id)
        logger.info("Model loaded.")

    def transcribe(
        self,
        file_path: Path,
        fmt: OutputFormat = OutputFormat.txt,
    ) -> TranscribeResult:
        self.load()

        wav_path, is_temp = prepare_audio(file_path)
        try:
            duration = get_duration(wav_path) or get_duration(file_path)
            config = DecodingConfig(decoding=Greedy())

            result: AlignedResult = self._model.transcribe(
                wav_path,
                dtype=mx.bfloat16,
                decoding_config=config,
                chunk_duration=CHUNK_DURATION,
                overlap_duration=OVERLAP_DURATION,
            )

            formatted = self._format(result, fmt)
            sentences = [
                Sentence(
                    text=s.text.strip(),
                    start=s.start,
                    end=s.end,
                    confidence=s.confidence,
                )
                for s in result.sentences
            ]

            return TranscribeResult(
                text=result.text,
                sentences=sentences,
                duration_seconds=duration,
                format=fmt,
                formatted_output=formatted,
            )
        finally:
            if is_temp:
                wav_path.unlink(missing_ok=True)

    @staticmethod
    def _format(result: AlignedResult, fmt: OutputFormat) -> str:
        if fmt == OutputFormat.txt:
            return to_txt(result)
        if fmt == OutputFormat.srt:
            return to_srt(result)
        if fmt == OutputFormat.vtt:
            return to_vtt(result)
        if fmt == OutputFormat.json:
            data = {
                "text": result.text,
                "sentences": [
                    {
                        "text": s.text.strip(),
                        "start": s.start,
                        "end": s.end,
                        "confidence": s.confidence,
                        "tokens": [
                            {"text": t.text, "start": t.start, "end": t.end, "confidence": t.confidence}
                            for t in s.tokens
                        ],
                    }
                    for s in result.sentences
                ],
            }
            return json.dumps(data, indent=2)
        return to_txt(result)


engine = TranscriptionEngine()
