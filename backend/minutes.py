from __future__ import annotations

import logging
import subprocess
import time

import httpx

logger = logging.getLogger(__name__)

QWEN_LOCAL_PORT = 18080
QWEN_URL = f"http://127.0.0.1:{QWEN_LOCAL_PORT}/v1/chat/completions"
QWEN_MODEL = "mlx-community/Qwen3.5-35B-A3B-4bit"
TIMEOUT = 300.0

_tunnel_proc: subprocess.Popen | None = None


def _ensure_tunnel() -> bool:
    """Ensure SSH tunnel to Mini's Qwen is up. Returns True if tunnel is available."""
    global _tunnel_proc

    # Check if tunnel is already working
    if _tunnel_proc is not None and _tunnel_proc.poll() is None:
        return True

    # Check if port is already forwarded (maybe from another process)
    try:
        with httpx.Client(timeout=3) as c:
            r = c.get(f"http://127.0.0.1:{QWEN_LOCAL_PORT}/v1/models")
            if r.status_code == 200:
                return True
    except Exception:
        pass

    # Start SSH tunnel: local 18080 -> mini's 127.0.0.1:8080
    logger.info("Starting SSH tunnel to Mini Qwen (localhost:%d -> mini:8080)", QWEN_LOCAL_PORT)
    try:
        _tunnel_proc = subprocess.Popen(
            ["ssh", "-N", "-L", f"{QWEN_LOCAL_PORT}:127.0.0.1:8080", "mini",
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


MINUTES_PROMPT = """You are an expert meeting-minutes writer. Given the transcript below, produce structured meeting minutes in Markdown.

Include:
- **Date / Location** (infer from context if possible)
- **Attendees** (names and roles mentioned)
- **Summary** (2-3 sentence overview)
- **Agenda Items** (each topic discussed, with key points)
- **Decisions Made** (any votes, approvals, or conclusions)
- **Action Items** (task, owner, deadline if mentioned)
- **Next Steps / Follow-ups**

Be concise. Attribute statements to speakers where the transcript makes it clear. Do not fabricate information not present in the transcript.

---
TRANSCRIPT:
{transcript}
---

MEETING MINUTES:"""


async def generate_minutes(transcript: str) -> str:
    if not _ensure_tunnel():
        return "*(Minutes generation unavailable — cannot establish SSH tunnel to Mini)*\n\nRaw transcript attached above."

    prompt = MINUTES_PROMPT.format(transcript=transcript)

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
            return data["choices"][0]["message"]["content"]
        except httpx.ConnectError:
            logger.warning("Could not reach Qwen through tunnel")
            return "*(Minutes generation unavailable — Qwen not reachable through tunnel)*\n\nRaw transcript attached above."
        except Exception:
            logger.exception("Minutes generation failed")
            return "*(Minutes generation failed — see backend logs)*"
