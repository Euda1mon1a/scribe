# Scribe

Local, privacy-preserving transcription and meeting minutes for macOS.

- **STT Engine**: Parakeet TDT (Nvidia) via MLX on Apple Silicon
- **Minutes**: Qwen 3.5-35B on Mac Mini (OpenAI-compatible, fully local)
- **Interface**: SwiftUI drag-and-drop app + MCP server for LLM integration

## Quick Start

```bash
# Install dependencies
uv pip install --system -e .

# Start backend
python3 -m backend.main
# → http://localhost:8890

# Test
curl -X POST http://localhost:8890/transcribe/path?path=/path/to/audio.wav
```

## MCP Integration

Add to your LLM CLI config (Claude, Gemini, Codex):
```json
"scribe": {
  "type": "http",
  "url": "http://127.0.0.1:8890/mcp"
}
```

Tools: `transcribe_file`, `generate_minutes`

## Architecture

```
SwiftUI App → localhost:8890 → Parakeet TDT (local STT)
MCP Clients → localhost:8890 → Qwen 3.5-35B (local minutes)
```
