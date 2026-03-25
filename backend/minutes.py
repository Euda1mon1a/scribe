from __future__ import annotations

import logging

import httpx

logger = logging.getLogger(__name__)

QWEN_URL = "http://100.69.127.98:8080/v1/chat/completions"
QWEN_MODEL = "mlx-community/Qwen3.5-35B-A3B-4bit"
TIMEOUT = 300.0

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
            logger.warning("Could not reach Qwen on Mini — returning transcript only")
            return "*(Minutes generation unavailable — Qwen not reachable on Mini)*\n\nRaw transcript attached above."
        except Exception:
            logger.exception("Minutes generation failed")
            return "*(Minutes generation failed — see backend logs)*"
