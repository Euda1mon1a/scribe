# Scribe

Local, privacy-preserving meeting transcription and minutes for macOS. Nothing leaves your machine.

Drop an audio or video file into the app, get a transcript and structured meeting minutes back. Record directly in the app if you prefer. Everything runs on your hardware — no cloud APIs, no data exfiltration, no subscriptions.

## What It Does

1. **Speech-to-text** via [Parakeet TDT](https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3) — Nvidia's speech model running on Apple MLX (GPU-accelerated on Apple Silicon). ~600MB model, processes audio in 2-minute chunks.
2. **Meeting minutes** via any OpenAI-compatible LLM — takes the transcript and produces attendees, agenda, decisions, action items. Works with local models (Qwen, Llama, Mistral via mlx-lm/ollama/vLLM) or remote APIs.
3. **MCP server** for LLM tools — Claude Code, Gemini CLI, or any MCP client can transcribe files and generate minutes directly.

## Install

**Requirements:** macOS 15+ on Apple Silicon, Python 3.12+, ffmpeg.

```bash
# Install ffmpeg if you don't have it
brew install ffmpeg

# Install the backend
pip install scribe-minutes
# or: uv pip install scribe-minutes

# Start it
scribe
# → Backend running at http://localhost:8890
```

### From source

```bash
git clone https://github.com/Euda1mon1a/scribe.git
cd scribe
pip install -e .   # or: uv pip install -e .
scribe
```

### macOS App

The native SwiftUI app provides drag-drop, recording, and a two-pane results view. Requires [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
make app-install    # builds and copies to /Applications
```

Or build manually:
```bash
cd app
xcodegen generate
xcodebuild -project Scribe.xcodeproj -scheme Scribe_macOS -destination 'platform=macOS' build
```

### iOS App

The repo includes an iOS target with recording, file import, and a share extension. To build it:

1. Open `app/project.yml` and set `DEVELOPMENT_TEAM` to your Apple Developer team ID
2. Update the bundle ID prefix (`bundleIdPrefix`) if needed
3. Build the `Scribe_iOS` scheme in Xcode

The iOS app points to `localhost:8890` by default — set the `scribeBackendURL` UserDefaults key to your server's IP if the backend runs on a different machine.

## Configuration

All configuration is via environment variables. None are required — the backend works out of the box for transcription. Minutes generation needs an LLM.

| Variable | Default | Description |
|----------|---------|-------------|
| `SCRIBE_LLM_URL` | `http://127.0.0.1:18080/v1/chat/completions` | OpenAI-compatible chat endpoint for minutes |
| `SCRIBE_LLM_MODEL` | `mlx-community/Qwen3.5-35B-A3B-4bit` | Model name to request |
| `SCRIBE_LLM_HOST` | *(empty)* | SSH host for auto-tunnel to remote LLM (e.g. `my-server`) |
| `SCRIBE_LLM_REMOTE_PORT` | `8080` | LLM port on remote host |
| `SCRIBE_LLM_LOCAL_PORT` | `18080` | Local port for SSH tunnel |
| `SCRIBE_LLM_TIMEOUT` | `300` | LLM request timeout (seconds) |
| `SCRIBE_RAG_URL` | *(empty)* | Optional RAG MCP endpoint for name/role correction |
| `SCRIBE_DEVONTHINK_GROUP` | *(empty)* | DEVONthink group UUID for export (saves to inbox if unset) |

### Example setups

**Local LLM via Ollama:**
```bash
export SCRIBE_LLM_URL=http://127.0.0.1:11434/v1/chat/completions
export SCRIBE_LLM_MODEL=qwen2.5:32b
scribe
```

**Remote LLM via SSH tunnel:**
```bash
export SCRIBE_LLM_HOST=my-gpu-server
export SCRIBE_LLM_REMOTE_PORT=8080
scribe
# Backend auto-creates: ssh -N -L 18080:127.0.0.1:8080 my-gpu-server
```

**Transcription only (no LLM needed):**
```bash
scribe
# Just use "Transcript Only" mode in the app, or the /transcribe API endpoint
```

## MCP Integration

LLM tools (Claude Code, etc.) can transcribe files directly.

Add to your MCP config:
```json
{
  "scribe": {
    "type": "http",
    "url": "http://127.0.0.1:8890/mcp"
  }
}
```

**Tools:**
- `transcribe_file(path, format)` — speech-to-text (txt, srt, vtt, json)
- `generate_minutes(path)` — transcript + structured minutes
- `batch_minutes(paths)` — process multiple files
- `get_latest_output()` — read the most recent result

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Backend status |
| `/transcribe` | POST | Upload file → transcript |
| `/transcribe/path?path=...` | POST | Local file → transcript |
| `/minutes` | POST | Upload file → transcript + minutes |
| `/minutes/path?path=...` | POST | Local file → transcript + minutes |
| `/batch/minutes` | POST | Multiple files → batch results |
| `/output/list` | GET | List saved outputs |
| `/output/latest` | GET | Latest output as markdown |
| `/export/devonthink` | POST | Save to DEVONthink (macOS) |

## Architecture

```
┌──────────────────────────────────┐
│  SwiftUI App                     │  Native macOS: drag-drop, recording,
│  Record / Open / Batch           │  Liquid Glass UI, keyboard shortcuts
└──────────┬───────────────────────┘
           │ localhost:8890
┌──────────▼───────────────────────┐
│  Python FastAPI Backend          │
│  ├─ Parakeet TDT (STT on MLX)   │  ~600MB, runs on Apple GPU
│  ├─ ffmpeg (audio extraction)    │  video → 16kHz mono WAV
│  ├─ LLM client (minutes)        │  any OpenAI-compatible endpoint
│  └─ /mcp endpoint                │  MCP server for LLM tools
└──────────────────────────────────┘
```

Three ways to use the same backend:
1. **SwiftUI app** — drag-drop GUI
2. **MCP tools** — Claude/Gemini/Codex transcribe via tool calls
3. **REST API** — curl, scripts, integrations

## macOS App Features

- Drag-drop or Cmd+O for single files, Cmd+Shift+O for batch
- Built-in audio recorder (click Record, speak, get minutes)
- Liquid Glass UI (macOS 26+)
- Two-pane results: transcript left, rendered markdown minutes right
- Keyboard shortcuts: Cmd+S (save), Cmd+E (DEVONthink), Cmd+Shift+C (copy minutes), Cmd+N (new)
- Drag transcript/minutes directly into other apps
- Recent transcriptions on the home screen
- System notification when processing completes
- DEVONthink export (macOS)

## License

MIT
