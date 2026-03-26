from __future__ import annotations

import logging
import os
import re
import subprocess
import time

import httpx

logger = logging.getLogger(__name__)

# --- Configuration (all overridable via environment) ---
# LLM for minutes generation (any OpenAI-compatible endpoint)
QWEN_URL = os.environ.get("SCRIBE_LLM_URL", "http://127.0.0.1:18080/v1/chat/completions")
QWEN_MODEL = os.environ.get("SCRIBE_LLM_MODEL", "mlx-community/Qwen3.5-35B-A3B-4bit")

# SSH tunnel to remote LLM (set SCRIBE_LLM_HOST to enable auto-tunnel, e.g. "mini")
LLM_HOST = os.environ.get("SCRIBE_LLM_HOST", "")  # empty = no tunnel, use LLM_URL directly
LLM_REMOTE_PORT = int(os.environ.get("SCRIBE_LLM_REMOTE_PORT", "8080"))
LLM_LOCAL_PORT = int(os.environ.get("SCRIBE_LLM_LOCAL_PORT", "18080"))

# RAG context server (optional, for name/role correction in minutes)
RAG_URL = os.environ.get("SCRIBE_RAG_URL", "")  # empty = skip RAG

TIMEOUT = float(os.environ.get("SCRIBE_LLM_TIMEOUT", "300"))

_tunnel_proc: subprocess.Popen | None = None


def _ensure_tunnel() -> bool:
    """Ensure SSH tunnel to remote LLM is up. Returns True if LLM is reachable."""
    global _tunnel_proc

    # If no SSH host configured, assume LLM_URL is directly reachable
    if not LLM_HOST:
        return True

    # Check if tunnel is already working
    if _tunnel_proc is not None and _tunnel_proc.poll() is None:
        return True

    # Check if port is already forwarded (maybe from another process)
    try:
        with httpx.Client(timeout=3) as c:
            r = c.get(f"http://127.0.0.1:{LLM_LOCAL_PORT}/v1/models")
            if r.status_code == 200:
                return True
    except Exception:
        pass

    # Start SSH tunnel
    logger.info("Starting SSH tunnel to %s (localhost:%d -> %s:%d)",
                LLM_HOST, LLM_LOCAL_PORT, LLM_HOST, LLM_REMOTE_PORT)
    try:
        _tunnel_proc = subprocess.Popen(
            ["ssh", "-N", "-L", f"{LLM_LOCAL_PORT}:127.0.0.1:{LLM_REMOTE_PORT}", LLM_HOST,
             "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=30",
             "-o", "ExitOnForwardFailure=yes"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        time.sleep(2)
        if _tunnel_proc.poll() is not None:
            stderr = _tunnel_proc.stderr.read().decode() if _tunnel_proc.stderr else ""
            logger.error("SSH tunnel failed: %s", stderr)
            _tunnel_proc = None
            return False
        logger.info("SSH tunnel established.")
        return True
    except Exception:
        logger.exception("Failed to start SSH tunnel")
        _tunnel_proc = None
        return False


async def _query_rag(query: str) -> str:
    """Query RAG server for context (names, roles, etc.). Returns empty string on failure or if disabled."""
    if not RAG_URL:
        return ""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                RAG_URL,
                json={
                    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
                    "params": {"name": "rag_search", "arguments": {"query": query, "top_k": 5}},
                },
            )
            if resp.status_code == 200:
                data = resp.json()
                content = data.get("result", {}).get("content", [])
                if content:
                    return content[0].get("text", "")
    except Exception:
        logger.debug("RAG query failed (non-critical), proceeding without context")
    return ""


MINUTES_PROMPT = """You are an expert meeting-minutes writer. Given the transcript below, produce structured meeting minutes in Markdown.

{rag_context}Include:
- **Date / Location** (infer from context if possible)
- **Attendees** (names and roles mentioned)
- **Summary** (2-3 sentence overview)
- **Agenda Items** (each topic discussed, with key points)
- **Decisions Made** (any votes, approvals, or conclusions)
- **Action Items** (task, owner, deadline if mentioned)
- **Next Steps / Follow-ups**

Be concise. Attribute statements to speakers where the transcript makes it clear. Use the reference information above to correct name spellings and identify roles. Do not fabricate information not present in the transcript.

---
TRANSCRIPT:
{transcript}
---

MEETING MINUTES:"""


async def generate_minutes(transcript: str) -> str:
    if not _ensure_tunnel():
        return "*(Minutes generation unavailable — cannot reach LLM)*\n\nRaw transcript attached above."

    # Query RAG for context (names, roles, etc.)
    rag_text = await _query_rag("faculty residents roster names roles")
    rag_context = ""
    if rag_text:
        rag_context = f"**Reference information (use to correct name spellings and identify roles):**\n{rag_text}\n\n"
        logger.info("RAG context injected (%d chars)", len(rag_text))

    prompt = MINUTES_PROMPT.format(transcript=transcript, rag_context=rag_context)

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        try:
            resp = await client.post(
                QWEN_URL,
                json={
                    "model": QWEN_MODEL,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 4096,
                    "temperature": 0.3,
                },
            )
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"]
            # Strip <think> reasoning tags if present (Qwen/DeepSeek)
            content = re.sub(r"<think>.*?</think>\s*", "", content, flags=re.DOTALL)
            content = re.sub(r"^Thinking Process:.*?(?=^#|\Z)", "", content, flags=re.DOTALL | re.MULTILINE)
            return content.strip()
        except httpx.ConnectError:
            logger.warning("Could not reach LLM at %s", QWEN_URL)
            return "*(Minutes generation unavailable — LLM not reachable)*\n\nRaw transcript attached above."
        except Exception:
            logger.exception("Minutes generation failed")
            return "*(Minutes generation failed — see backend logs)*"
