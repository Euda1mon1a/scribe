"""DEVONthink integration via AppleScript (macOS only)."""
from __future__ import annotations

import logging
import subprocess
from datetime import datetime

logger = logging.getLogger(__name__)

# Target group UUID for Meeting Minutes in DEVONthink
MEETING_MINUTES_GROUP = "88207AFC-8A12-42E8-8552-8DE5D99FF516"


def save_to_devonthink(
    title: str,
    content: str,
    tags: list[str] | None = None,
    group_uuid: str = MEETING_MINUTES_GROUP,
) -> bool:
    """Save markdown content to DEVONthink via AppleScript. Returns True on success."""
    if tags is None:
        tags = ["minutes", "scribe"]

    date_str = datetime.now().strftime("%Y-%m-%d")
    record_name = f"{title} — {date_str}"

    # Escape content for AppleScript
    escaped_content = content.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    escaped_name = record_name.replace('"', '\\"')
    tag_list = ", ".join(f'"{t}"' for t in tags)

    script = f'''
    tell application "DEVONthink 3"
        set theGroup to get record with uuid "{group_uuid}"
        set theRecord to create record with {{name:"{escaped_name}", type:markdown, plain text:"{escaped_content}"}} in theGroup
        set tags of theRecord to {{{tag_list}}}
        return uuid of theRecord
    end tell
    '''

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            uuid = result.stdout.strip()
            logger.info("Saved to DEVONthink: %s (uuid: %s)", record_name, uuid)
            return True
        else:
            logger.error("DEVONthink AppleScript failed: %s", result.stderr)
            return False
    except FileNotFoundError:
        logger.warning("osascript not available — not on macOS?")
        return False
    except subprocess.TimeoutExpired:
        logger.error("DEVONthink AppleScript timed out")
        return False
    except Exception:
        logger.exception("DEVONthink save failed")
        return False
