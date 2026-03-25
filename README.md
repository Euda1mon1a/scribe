# Scribe

Local, privacy-preserving transcription and meeting minutes for macOS. Nothing leaves your machine.

## How It Works

When you drop a file into the app, here's what happens:

1. **The app sends the file to the backend.** The SwiftUI app uploads your file over HTTP to a Python server running on your own machine (localhost:8890). Nothing leaves your computer.

2. **Audio extraction.** If it's a video file (MP4, MOV, etc.), the backend uses ffmpeg to strip out just the audio track and convert it to a WAV file at 16kHz mono — the format the speech model expects.

3. **Speech-to-text (Parakeet TDT).** The audio goes into Parakeet TDT, a speech recognition model from Nvidia that runs on Apple's MLX framework (Apple's GPU-optimized ML runtime for M-series chips). The ~600MB model lives entirely on your machine. It processes audio in 2-minute chunks with 15-second overlaps so it doesn't miss words at boundaries. Each chunk is converted to a mel spectrogram (a visual representation of sound frequencies over time), fed through a conformer neural network, and decoded into text with timestamps and confidence scores for every word.

4. **Minutes generation.** If you selected "Transcript + Minutes" mode, the full transcript is sent to Qwen 3.5-35B running on the Mac Mini over Tailscale. That's a 35-billion-parameter language model running locally on the Mini's GPU. It reads the transcript and produces structured meeting minutes — attendees, agenda items, decisions, action items.

5. **Results back to the app.** The backend returns transcript + minutes as JSON. The app displays them side-by-side — transcript on the left, minutes on the right. You can copy either to clipboard or save as a file.

**The whole chain is local.** Your audio never touches OpenAI, Google, or any cloud service. The only network hop is laptop → Mini over your private Tailscale VPN for the minutes step.

## Quick Start

```bash
# Install dependencies (one time)
brew install ffmpeg
uv pip install --system parakeet-mlx fastapi "uvicorn[standard]" httpx python-multipart

# Start backend
cd ~/Projects/scribe
python3 -m backend.main
# → http://localhost:8890

# Build and launch the app (separate terminal)
cd ~/Projects/scribe/app
swift build && open .build/debug/Scribe
```

Drop any audio or video file onto the window.

## MCP Integration

LLM CLIs (Claude Code, Gemini, Codex) can transcribe files directly via MCP tools.

Add to your CLI config:
```json
"scribe": {
  "type": "http",
  "url": "http://127.0.0.1:8890/mcp"
}
```

**Tools:**
- `transcribe_file(path, format)` — transcribe an audio/video file to text, SRT, VTT, or JSON
- `generate_minutes(path)` — transcribe and generate structured meeting minutes

## Architecture

```
┌─────────────────────────────┐
│  SwiftUI App (drag & drop)  │  ← Native macOS UI
│  Calls backend via HTTP     │
└──────────┬──────────────────┘
           │ localhost:8890
┌──────────▼──────────────────┐
│  Python FastAPI Backend     │  ← Core engine
│  ├─ parakeet_mlx (STT)     │  ~600MB model, runs on Apple GPU
│  ├─ ffmpeg (audio extract)  │  video → 16kHz mono WAV
│  ├─ Qwen 3.5-35B (minutes) │  → Mini:8080 via Tailscale
│  └─ /mcp endpoint           │  ← MCP server for LLM CLIs
└─────────────────────────────┘
```

Three consumers of the same backend:
1. **SwiftUI app** — drag-drop GUI for humans
2. **MCP server** — Claude/Gemini/Codex can transcribe files via tools
3. **API** — `curl` / any HTTP client

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Backend status + model loaded |
| `/transcribe` | POST | Upload file, get transcript |
| `/transcribe/path` | POST | Transcribe local file by path |
| `/minutes` | POST | Upload file, get transcript + minutes |
| `/minutes/path` | POST | Local file → transcript + minutes |
| `/mcp` | POST | MCP protocol (tool discovery + execution) |

## Requirements

- macOS 15+ (Apple Silicon)
- Python 3.12+ via pyenv
- ffmpeg (via Homebrew)
- Mac Mini with Qwen 3.5-35B on port 8080 (for minutes generation; transcription works without it)
