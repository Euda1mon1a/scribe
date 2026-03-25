from __future__ import annotations

import logging
import shutil
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse

from backend.minutes import generate_minutes
from backend.models import HealthResponse, MinutesResult, OutputFormat, TranscribeResult
from backend.transcriber import engine

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Scribe backend starting — preloading model...")
    engine.load()
    logger.info("Model ready.")
    yield


app = FastAPI(title="Scribe", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _save_upload(upload: UploadFile) -> Path:
    suffix = Path(upload.filename).suffix if upload.filename else ".tmp"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    shutil.copyfileobj(upload.file, tmp)
    tmp.close()
    return Path(tmp.name)


@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(
        status="ok",
        model_loaded=engine.loaded,
        model_name=engine.model_name if engine.loaded else None,
    )


@app.post("/transcribe", response_model=TranscribeResult)
async def transcribe(
    file: UploadFile = File(...),
    format: OutputFormat = Query(OutputFormat.txt),
):
    tmp_path = _save_upload(file)
    try:
        return engine.transcribe(tmp_path, fmt=format)
    finally:
        tmp_path.unlink(missing_ok=True)


@app.post("/transcribe/path", response_model=TranscribeResult)
async def transcribe_path(
    path: str = Query(..., description="Absolute path to audio/video file"),
    format: OutputFormat = Query(OutputFormat.txt),
):
    """Transcribe a local file by path (used by MCP tools)."""
    file_path = Path(path)
    if not file_path.exists():
        return PlainTextResponse(f"File not found: {path}", status_code=404)
    return engine.transcribe(file_path, fmt=format)


@app.post("/minutes", response_model=MinutesResult)
async def minutes(file: UploadFile = File(...)):
    tmp_path = _save_upload(file)
    try:
        result = engine.transcribe(tmp_path, fmt=OutputFormat.txt)
        mins = await generate_minutes(result.text)
        return MinutesResult(
            transcript=result.text,
            minutes=mins,
            duration_seconds=result.duration_seconds,
        )
    finally:
        tmp_path.unlink(missing_ok=True)


@app.post("/minutes/path", response_model=MinutesResult)
async def minutes_path(
    path: str = Query(..., description="Absolute path to audio/video file"),
):
    """Transcribe and generate minutes for a local file (used by MCP tools)."""
    file_path = Path(path)
    if not file_path.exists():
        return PlainTextResponse(f"File not found: {path}", status_code=404)
    result = engine.transcribe(file_path, fmt=OutputFormat.txt)
    mins = await generate_minutes(result.text)
    return MinutesResult(
        transcript=result.text,
        minutes=mins,
        duration_seconds=result.duration_seconds,
    )


# --- MCP Protocol ---

MCP_TOOLS = [
    {
        "name": "transcribe_file",
        "description": "Transcribe an audio or video file to text using Parakeet TDT (local, private). Returns timestamped transcript.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute path to the audio/video file"},
                "format": {"type": "string", "enum": ["txt", "srt", "vtt", "json"], "default": "txt"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "generate_minutes",
        "description": "Transcribe an audio/video file and generate structured meeting minutes using local LLM (Qwen on Mini).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute path to the audio/video file"},
            },
            "required": ["path"],
        },
    },
]


@app.post("/mcp")
async def mcp_handler(request: dict):
    method = request.get("method", "")
    req_id = request.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0", "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "scribe", "version": "0.1.0"},
            },
        }

    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": MCP_TOOLS}}

    if method == "tools/call":
        params = request.get("params", {})
        tool_name = params.get("name")
        args = params.get("arguments", {})

        if tool_name == "transcribe_file":
            file_path = Path(args["path"])
            if not file_path.exists():
                return _mcp_error(req_id, f"File not found: {args['path']}")
            fmt = OutputFormat(args.get("format", "txt"))
            result = engine.transcribe(file_path, fmt=fmt)
            return _mcp_result(req_id, result.formatted_output)

        if tool_name == "generate_minutes":
            file_path = Path(args["path"])
            if not file_path.exists():
                return _mcp_error(req_id, f"File not found: {args['path']}")
            result = engine.transcribe(file_path, fmt=OutputFormat.txt)
            mins = await generate_minutes(result.text)
            return _mcp_result(req_id, f"# Transcript\n\n{result.text}\n\n---\n\n# Minutes\n\n{mins}")

        return _mcp_error(req_id, f"Unknown tool: {tool_name}")

    if method in ("notifications/initialized", "notifications/cancelled"):
        return {"jsonrpc": "2.0", "id": req_id, "result": {}}

    return _mcp_error(req_id, f"Unknown method: {method}")


def _mcp_result(req_id, text: str) -> dict:
    return {
        "jsonrpc": "2.0", "id": req_id,
        "result": {"content": [{"type": "text", "text": text}]},
    }


def _mcp_error(req_id, msg: str) -> dict:
    return {
        "jsonrpc": "2.0", "id": req_id,
        "result": {"content": [{"type": "text", "text": f"Error: {msg}"}], "isError": True},
    }


def cli():
    import uvicorn
    uvicorn.run("backend.main:app", host="127.0.0.1", port=8890, log_level="info")


if __name__ == "__main__":
    cli()
