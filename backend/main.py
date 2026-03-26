from __future__ import annotations

import logging
import shutil
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Query, UploadFile
from pydantic import BaseModel as BaseSchema
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse

from backend.devonthink import save_to_devonthink
from backend.minutes import generate_minutes
from backend.models import BatchItem, BatchResult, HealthResponse, MinutesResult, OutputFormat, TranscribeResult
from backend.transcriber import engine

OUTPUT_DIR = Path.home() / "Documents" / "scribe-output"

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


def _persist_output(source_name: str, transcript: str, minutes: str = "", duration: float = 0) -> Path:
    """Save output to ~/Documents/scribe-output/ for LLM access."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = Path(source_name).stem
    out_path = OUTPUT_DIR / f"{stem}-minutes.md"
    content = f"# Scribe Output: {source_name}\n\n"
    content += f"**Duration:** {int(duration // 60)}m {int(duration % 60)}s\n\n"
    if minutes:
        content += f"## Minutes\n\n{minutes}\n\n---\n\n"
    content += f"## Transcript\n\n{transcript}\n"
    out_path.write_text(content, encoding="utf-8")
    # Also write a "latest" symlink
    latest = OUTPUT_DIR / "latest.md"
    latest.unlink(missing_ok=True)
    latest.symlink_to(out_path)
    logger.info("Output saved: %s", out_path)
    return out_path


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
        result = engine.transcribe(tmp_path, fmt=format)
        _persist_output(file.filename or "untitled", result.text, duration=result.duration_seconds)
        return result
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
        _persist_output(file.filename or "untitled", result.text, mins, result.duration_seconds)
        return MinutesResult(
            transcript=result.text,
            minutes=mins,
            duration_seconds=result.duration_seconds,
        )
    finally:
        tmp_path.unlink(missing_ok=True)


@app.post("/batch/minutes", response_model=BatchResult)
async def batch_minutes(files: list[UploadFile] = File(...)):
    """Process multiple files sequentially — transcribe + generate minutes for each."""
    items: list[BatchItem] = []
    for upload in files:
        tmp_path = _save_upload(upload)
        fname = upload.filename or "untitled"
        try:
            result = engine.transcribe(tmp_path, fmt=OutputFormat.txt)
            mins = await generate_minutes(result.text)
            _persist_output(fname, result.text, mins, result.duration_seconds)
            items.append(BatchItem(
                filename=fname, transcript=result.text, minutes=mins,
                duration_seconds=result.duration_seconds, status="ok",
            ))
        except Exception as e:
            logger.exception("Batch item failed: %s", fname)
            items.append(BatchItem(
                filename=fname, transcript="", minutes="",
                duration_seconds=0, status="error", error=str(e),
            ))
        finally:
            tmp_path.unlink(missing_ok=True)

    completed = sum(1 for i in items if i.status == "ok")
    return BatchResult(total=len(items), completed=completed, failed=len(items) - completed, items=items)


@app.post("/batch/minutes/paths", response_model=BatchResult)
async def batch_minutes_paths(paths: list[str]):
    """Process multiple local files by path — for MCP and CLI use."""
    items: list[BatchItem] = []
    for p in paths:
        file_path = Path(p)
        if not file_path.exists():
            items.append(BatchItem(
                filename=file_path.name, transcript="", minutes="",
                duration_seconds=0, status="error", error=f"File not found: {p}",
            ))
            continue
        try:
            result = engine.transcribe(file_path, fmt=OutputFormat.txt)
            mins = await generate_minutes(result.text)
            _persist_output(file_path.name, result.text, mins, result.duration_seconds)
            items.append(BatchItem(
                filename=file_path.name, transcript=result.text, minutes=mins,
                duration_seconds=result.duration_seconds, status="ok",
            ))
        except Exception as e:
            logger.exception("Batch item failed: %s", file_path.name)
            items.append(BatchItem(
                filename=file_path.name, transcript="", minutes="",
                duration_seconds=0, status="error", error=str(e),
            ))

    completed = sum(1 for i in items if i.status == "ok")
    return BatchResult(total=len(items), completed=completed, failed=len(items) - completed, items=items)


class DevonThinkExport(BaseSchema):
    title: str
    content: str
    tags: list[str] | None = None


@app.post("/export/devonthink")
async def export_to_devonthink_endpoint(body: DevonThinkExport):
    """Save content to DEVONthink Meeting Minutes group (macOS only)."""
    ok = save_to_devonthink(body.title, body.content, tags=body.tags)
    if ok:
        return {"status": "saved", "title": body.title}
    return PlainTextResponse("DEVONthink save failed — check backend logs", status_code=500)


@app.get("/output/latest")
async def get_latest_output():
    """Get the latest transcription/minutes output (for LLMs to read)."""
    latest = OUTPUT_DIR / "latest.md"
    if not latest.exists():
        return PlainTextResponse("No output yet", status_code=404)
    return PlainTextResponse(latest.read_text(encoding="utf-8"))


@app.get("/output/list")
async def list_outputs():
    """List all saved outputs."""
    if not OUTPUT_DIR.exists():
        return {"outputs": []}
    files = sorted(OUTPUT_DIR.glob("*-minutes.md"), key=lambda f: f.stat().st_mtime, reverse=True)
    return {"outputs": [{"name": f.name, "path": str(f), "size": f.stat().st_size} for f in files]}


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
    _persist_output(file_path.name, result.text, mins, result.duration_seconds)
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
        "description": "Transcribe an audio/video file and generate structured meeting minutes using local LLM (Qwen on Mini). Uses RAG for name/role correction.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute path to the audio/video file"},
            },
            "required": ["path"],
        },
    },
    {
        "name": "batch_minutes",
        "description": "Transcribe multiple audio/video files and generate minutes for each. Processes sequentially.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "paths": {"type": "array", "items": {"type": "string"}, "description": "List of absolute file paths"},
            },
            "required": ["paths"],
        },
    },
    {
        "name": "get_latest_output",
        "description": "Get the latest transcription/minutes output as markdown. Use this to read results after transcription completes.",
        "inputSchema": {
            "type": "object",
            "properties": {},
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
            _persist_output(file_path.name, result.text, mins, result.duration_seconds)
            return _mcp_result(req_id, f"# Transcript\n\n{result.text}\n\n---\n\n# Minutes\n\n{mins}")

        if tool_name == "batch_minutes":
            paths = args.get("paths", [])
            results = []
            for p in paths:
                fp = Path(p)
                if not fp.exists():
                    results.append(f"## {fp.name}\n\nError: File not found")
                    continue
                try:
                    result = engine.transcribe(fp, fmt=OutputFormat.txt)
                    mins = await generate_minutes(result.text)
                    _persist_output(fp.name, result.text, mins, result.duration_seconds)
                    results.append(f"## {fp.name}\n\n{mins}")
                except Exception as e:
                    results.append(f"## {fp.name}\n\nError: {e}")
            return _mcp_result(req_id, "\n\n---\n\n".join(results))

        if tool_name == "get_latest_output":
            latest = OUTPUT_DIR / "latest.md"
            if not latest.exists():
                return _mcp_error(req_id, "No output yet — transcribe a file first")
            return _mcp_result(req_id, latest.read_text(encoding="utf-8"))

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
