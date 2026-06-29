# Black God PWA — UI Kit

High-fidelity recreation of the Black God mobile PWA in the **Obsidian Chrome** language. Recreated from `web/index.html` (v3.0) in the private review repo — not from screenshots.

## Run
Open `index.html`. It renders a 390×780 phone with three tabs and a bottom sheet.

## Screens
- **`ChatScreen.jsx`** (执行 tab) — the execution hub. User message → tool/cascade trace → an inline **consent prompt** (approve a write op) → closed-loop result with cost badge and an auto-distilled skill. Frosted top bar with the live provider pill; chrome composer.
- **`RecordsScreen.jsx`** (记忆 tab) — long-term memory + the cost dashboard. `StatTile`s (money saved, cache hit), a `CascadeBar` of today's L0–L6 distribution, memory rows (servers, projects, habits, no-go zones), and auto-distilled skill chips.
- **`ProfileScreen.jsx`** (我的 tab) — identity + **privacy guardrails** (local-first, PII detection, audit log, cloud-sync-off-by-default), Provider Hub entry, destructive "clear local memory".
- **`ProviderSheet.jsx`** — bottom sheet for the **bring-your-own** model gateway (DeepSeek / Anthropic / OpenAI / local), keys-stay-local note, add-custom-gateway.

## Composition
Every screen is built from the DS primitives on `window.BlackGodDesignSystem_7a1b36` — `Avatar, Badge, Button, Card, CascadeBar, Chip, IconButton, Input, StatTile, Switch`. Screens add only layout + product copy; no primitive is re-implemented.

## Fidelity notes
- Tab-bar glyphs are unicode placeholders (◈ ▤ ◉) — the source PWA uses the same lightweight glyph approach. Swap for Lucide if a committed icon set is added (see root readme ICONOGRAPHY).
- Cost/latency numbers are illustrative but formatted exactly as the product shows them (monospace, ¥ + seconds + level).
