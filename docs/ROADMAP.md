# Scribe Roadmap

## Current State (v0.1.0)
Personal tool: Python backend + SwiftUI app + MCP server. Developer setup only.

---

## Phase 1: Polish for Personal Use (Now)
- [ ] LaunchAgent for backend auto-start
- [ ] App auto-reconnect if backend restarts
- [ ] Push to Gitea for backup
- [ ] AAPM integration: transcribe APE meetings directly from scheduler

## Phase 2: Distributable macOS App (Future)
Target: Any M1+ Mac user can install from a .dmg without touching a terminal.

**Packaging:**
- Bundle Python runtime (~150MB) via py2app or PyInstaller
- Bundle static ffmpeg binary (~80MB)
- First-launch model download: Parakeet TDT (~600MB) to ~/Library/Application Support/Scribe/
- Total install: ~250MB + 600MB model download
- Code signing + notarization: Apple Developer account ($99/yr)

**Minutes for non-infrastructure users:**
- Option A: Bundle Phi-4-Mini (2.2GB download) — decent quality, runs on 8GB M1
- Option B: Bring-your-own API key (OpenAI/Anthropic) in preferences
- Option C: Transcription-only (minutes as optional upgrade)

**Effort estimate:** ~1 week of packaging and UX work

## Phase 3: iOS App (Exploratory)

**Core constraint:** MLX is macOS-only. iOS requires Core ML.

**Viable path:** WhisperKit (by Argmax) — Swift package running Whisper via Core ML on iPhone. Battle-tested, used in production apps. Loses Parakeet accuracy edge but proven iOS stack.

| Device | Model | Feasible? |
|--------|-------|-----------|
| iPhone 15 Pro+ | Whisper Large v3 Turbo | Yes (~4GB available) |
| iPhone 13/14 | Whisper Small/Medium | Yes (lower quality) |
| Older iPhones | Whisper Tiny/Base | Rough quality |

**Minutes on iOS:**
- On-device: Apple's foundation models in iOS 26 may enable this
- Cloud: API call to OpenAI/Claude (defeats privacy story)
- Skip: Transcription-only on mobile, minutes on Mac

**App Store considerations:**
- Apple takes 30%
- 1-2 week review process
- ~15 existing Whisper-based transcription apps already on store
- Differentiator would be meeting-minutes output, not transcription itself
- Can't claim "local and private" if any cloud fallback exists

**Alternative:** Parakeet TDT → Core ML conversion. Theoretically possible but uncharted — nobody has published a Core ML conversion of Parakeet. Would need to trace the model through coremltools. High effort, uncertain outcome.

## AAPM Integration Ideas
- Transcribe APE/curriculum committee meetings → auto-generate minutes → store in scheduler
- Attach transcripts to schedule review sessions
- Voice notes from coordinators → action items extracted automatically
- MCP tool `generate_minutes` already works — just needs a UI trigger in AAPM frontend
