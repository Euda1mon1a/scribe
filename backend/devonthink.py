"""DEVONthink integration via AppleScript (macOS only)."""
from __future__ import annotations

import logging
import os
import subprocess
from datetime import datetime

logger = logging.getLogger(__name__)

# Target group UUID in DEVONthink (set via env or pass per-call)
DEFAULT_GROUP_UUID = os.environ.get("SCRIBE_DEVONTHINK_GROUP", "")


def save_to_devonthink(
    title: str,
    content: str,
    tags: list[str] | None = None,
    group_uuid: str = "",
) -> bool:
    """Save markdown content to DEVONthink via AppleScript. Returns True on success.

    Set SCRIBE_DEVONTHINK_GROUP env var to your target group UUID,
    or pass group_uuid directly. If neither is set, saves to the global inbox.
    """
    uuid = group_uuid or DEFAULT_GROUP_UUID
    if tags is None:
        tags = ["minutes", "scribe"]

    date_str = datetime.now().strftime("%Y-%m-%d")
    record_name = f"{title} — {date_str}"

    # Escape content for AppleScript
    escaped_content = content.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    escaped_name = record_name.replace('"', '\\"')
    tag_list = ", ".join(f'"{t}"' for t in tags)

    if uuid:
        script = f'''
        tell application "DEVONthink"
            set theGroup to get record with uuid "{uuid}"
            set theRecord to create record with {{name:"{escaped_name}", type:markdown, plain text:"{escaped_content}"}} in theGroup
            set tags of theRecord to {{{tag_list}}}
            return uuid of theRecord
        end tell
        '''
    else:
        script = f'''
        tell application "DEVONthink"
            set theRecord to create record with {{name:"{escaped_name}", type:markdown, plain text:"{escaped_content}"}} in incoming group of database 1
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
