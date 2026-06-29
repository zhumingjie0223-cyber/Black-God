# Black God · Design System

> 一个真正懂你工作生活的助理 — *a private, multi-device execution hub that actually knows your work and life.*

Black God 不是平台聊天框，而是私人多端执行中枢。它连接你的手机、电脑、服务器、API、工具和记忆，把**执行权和数据**留在你自己手里。This design system captures its **"Obsidian Chrome"** visual language (PWA v3.0) so any new surface — app screen, marketing page, deck, investor doc — looks unmistakably Black God.

## Sources (input materials)
This system was reverse-engineered from the private review repo. If you have access, explore them to build with higher fidelity:
- **GitHub (source of truth):** https://github.com/BlackGod-B/blackgod-private-review
  - `web/index.html` — the v3.0 "Obsidian Chrome" PWA (the canonical visual reference)
  - `web/theme.css`, `web/css/style.css` — earlier "Imperial Gold" theme (legacy)
  - `CORE_PHILOSOPHY.md`, `ARCHITECTURE.md` — positioning, copy voice, the L0–L6 cascade
  - `web/logo.png`, `web/brand-hero-display.png` — the metallic 神 mark (imported to `assets/`)

The product is also published at **BlackGod-B/Blackgod** (Personal Agent OS). Read these repos to do a better job designing for the brand.

---

## What Black God is (product context)

A **personal Agent OS** — local-first, platform-agnostic, and built to *execute*, not just chat.

| Pillar | Meaning |
|---|---|
| 懂你工作生活 | Remembers your projects, habits, servers, no-go zones — no re-explaining |
| 本地优先 | Passwords, config, memory saved locally by default — never auto-uploaded |
| 不锁平台 | You bring your own API / Provider / tools — no single-vendor lock-in |
| 真执行 | Calls tools, verifies results, updates memory, completes the loop |
| 越用越强 | Learns from real tasks, compresses memory, **auto-distills skills** (this is automatic — never marketed as a "150+ skills" feature) |

**Signature technology to visualize:**
- **成本级联引擎 (Cost Cascade, L0–L6):** 缓存 → 规则 → 本地工具 → 便宜模型 → 贵模型 → 深度推理 → 人工. The request resolves at the cheapest viable level. → `CascadeBar` component.
- **模型网关 / Provider Hub:** one interface over OpenAI / Anthropic / DeepSeek / local / custom gateways.
- **Agent Loop:** multi-step reasoning + tool calls + self-reflection + memory update.
- **记忆系统:** short-term (session) + working (task) + long-term (profile + project knowledge).
- **隐私护栏:** PII detection + consent flow + audit log, local-first.

Stack: Python 3.11+ backend · HTML/CSS/JS **PWA** frontend · SQLite (local memory) · Cloudflare Workers (public demo).

---

## CONTENT FUNDAMENTALS — how Black God writes

- **Language:** Simplified Chinese first; technical nouns (Provider, API, Agent Loop, L0–L6, token) stay in English/code. Bilingual is fine in labels (`RECORDS · 记忆`).
- **Voice:** Speaks to **你** (you), refers to itself by name or 我 sparingly. Confident, terse, engineering-grade — like a senior operator, not a cheerful chatbot. *"把执行权和数据留在你自己手里。"* / *"不用每次重新解释。"*
- **Casing:** UI eyebrows are UPPERCASE + wide tracking (`RECORDS`, `PROVIDERS`). The wordmark is `BLACK GOD` (spaced caps). Body sentence-case.
- **Numbers are first-class.** Cost (¥0.0021), latency (1.24s), tokens, cache-hit % and the resolving cascade level appear in **monospace** as proof of the cost story. Show them; don't hide them.
- **No emoji as decoration.** A few functional glyphs appear in product chrome (🔒 local, 🔌 provider, ⚡ cache, ☁️ cloud) but the brand tone is metallic and serious — never playful. Avoid emoji in marketing/investor surfaces.
- **Claims are concrete and falsifiable:** "本月省下 ¥248 ↓ 62%" beats "saves you money."

---

## VISUAL FOUNDATIONS — "Obsidian Chrome"

- **Palette:** cool-toned near-blacks (`--bg #08090B` → `--bg-3 #1A1E25`) under thin white-alpha surface veils. The accent is **cold silver chrome** (`--chrome-1 #C8CED6` + the `--chrome-grad` brushed-metal gradient) — *never blue, never purple, never warm gold* (the gold `theme.css` is legacy, reserved for ceremony only). Semantic color (green/blue/amber/red) is the **only** other color and is reserved strictly for status.
- **Type:** platform **system stack** only (`-apple-system → PingFang SC`), no webfonts — the PWA must load instantly in China and render 中文 natively. Display & wordmark use the chrome gradient clipped to text. Mono (`SF Mono`) carries all cost/latency/token data. *(UI scale was bumped up — body is now 16.5px — for on-device legibility.)*
- **Backgrounds:** static metal **vignette + radial speculars** over obsidian (`--field-bg`). No animated gradients, no busy patterns, no imagery behind content except the hero 神 mark.
- **Surfaces / cards:** machined-metal panels — obsidian fill, single hairline edge (`--line`), a 1px top **inset specular** that reads as brushed metal (`--panel-chrome`). Radius 18px cards / 12px controls / pill chips. `chrome` variant adds the cold brand glow; `inset` is a recessed well for logs/terminals.
- **Buttons:** primary = brushed-chrome **plate** (dark ink on metal gradient) with a cold glow lift; secondary = chrome-outline; ghost = bare hairline; danger = red plate. The composer send is a filled chrome circle.
- **Shadows:** cool and deep (`rgba(0,0,0,.3–.65)`), paired with inset speculars. Glows are silver (`--chrome-glow`), low-opacity — light catching metal, not neon.
- **Borders:** hairlines everywhere (`--line` 8% white); the metal-edge variant `--line-chrome` (silver 22%) marks active/chrome elements.
- **Radii:** 9 / 12 / 18 / pill. Nothing fully sharp, nothing bubbly.
- **Motion:** restrained. `--ease-out` for most; `--ease-spring` overshoot only for the logo pop and switch knob; `--ease-sheet` for bottom-sheet slide-up. Fast (.15s) press feedback. No infinite/decorative loops.
- **States:** hover lifts surface veil one step + brightens chrome; **press shrinks** (scale .9–.97) and dims slightly — built into Button / IconButton / Pill. Focus = chrome ring (`--ring`).
- **Transparency & blur:** frosted bars/sheets use `--blur-bar` (28px) over white-alpha; reserved for floating chrome (top bar, bottom sheet), not content.
- **Imagery vibe:** cold, monochrome, metallic; the hero asset is the single 神 glyph in machined silver on black.

---

## ICONOGRAPHY

- Black God ships **no icon font and no SVG icon set** in the reviewed PWA — product chrome uses a small set of **functional emoji/unicode glyphs** (🔒 local-first, 🔌 provider, ⚡ cache, ☁️ cloud, ↑ send, ✕ close, 🔍 search) rendered in chrome tones, plus mono arrows for the cascade (`→`, `←`).
- The one true brand asset is the **metallic 神 mark** (`assets/logo-god.png`, 512×512; also `icon-192/512.png`, `brand-hero.png`, `brand-source.png`). Use it for the assistant `Avatar (kind="god")`, app icon, and hero.
- **When you need a real icon set** (app kit, dense toolbars), substitute **Lucide** (CDN) at 1.75px stroke, tinted `--chrome-2` — it matches the thin metallic line feel. **This is a substitution — flag it to the user** and ask whether they want a committed icon set added to the system. Never hand-draw SVG icons.

---

## INDEX (manifest)

**Root**
- `styles.css` — entry point (import this); `@import`s all tokens.
- `readme.md` — this guide. · `SKILL.md` — Agent-Skills wrapper.

**`tokens/`** — `colors.css` · `typography.css` · `spacing.css` · `effects.css` · `fonts.css` (intentionally empty — system fonts).

**`assets/`** — `logo-god.png`, `icon-192.png`, `icon-512.png`, `brand-hero.png`, `brand-source.png`.

**`components/`** (namespace `window.BlackGodDesignSystem_7a1b36`)
- `core/` — **Button**, **IconButton**, **Chip**, **Pill**, **Card**
- `forms/` — **Input**, **Switch**
- `data/` — **Badge**, **Avatar**, **StatTile**, **CascadeBar** *(signature L0–L6 viz)*

**`guidelines/`** — foundation specimen cards (Colors · Type · Spacing · Effects · Brand) shown in the Design System tab.

**`ui_kits/`** — *(in progress)* `app/` — the Black God mobile PWA recreation.

---

### Caveats / open items
- **Fonts:** no webfonts by design. The system stack references `SF Pro Text`; if a non-Apple device should match exactly, upload the licensed file or accept the fallback.
- **Icons** are substituted (Lucide) where a set is needed — see ICONOGRAPHY. Confirm the choice.
- **UI kit** (`ui_kits/app/`) is the next build step — see the project todo list.
