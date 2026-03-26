from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel


class OutputFormat(str, Enum):
    txt = "txt"
    srt = "srt"
    vtt = "vtt"
    json = "json"


class Sentence(BaseModel):
    text: str
    start: float
    end: float
    confidence: float


class TranscribeResult(BaseModel):
    text: str
    sentences: list[Sentence]
    duration_seconds: float
    format: OutputFormat
    formatted_output: str


class MinutesResult(BaseModel):
    transcript: str
    minutes: str
    duration_seconds: float


class BatchItem(BaseModel):
    filename: str
    transcript: str
    minutes: str
    duration_seconds: float
    status: str  # "ok" or "error"
    error: Optional[str] = None


class BatchResult(BaseModel):
    total: int
    completed: int
    failed: int
    items: list[BatchItem]


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    model_name: Optional[str] = None
