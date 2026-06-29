---
name: blackgod-design
description: Use this skill to generate well-branded interfaces and assets for Black God (黑神 · 一个真正懂你工作生活的助理 — a local-first, platform-agnostic personal Agent OS), either for production or throwaway prototypes/mocks/decks. Contains the "Obsidian Chrome" design language — colors, type, fonts, the metallic 神 brand asset, and reusable UI kit components.
user-invocable: true
---

Read the `readme.md` file within this skill, and explore the other available files.

Black God's look is **"Obsidian Chrome"**: cool near-black surfaces, machined-metal panels with inset speculars, and a single cold-silver chrome accent (never blue, purple, or warm gold). Type is the platform system stack (no webfonts). Semantic color is reserved strictly for status. Cost/latency/token numbers are first-class, in monospace. The signature visual is the **L0–L6 cost cascade** (`CascadeBar`). The one brand asset is the metallic **神** mark (`assets/logo-god.png`).

- `styles.css` — link this; it `@import`s every token.
- `tokens/` — colors, typography, spacing, effects.
- `components/` — React primitives on `window.BlackGodDesignSystem_7a1b36` (Button, IconButton, Chip, Pill, Card, Input, Switch, Badge, Avatar, StatTile, CascadeBar). Each has a `.prompt.md` with usage.
- `guidelines/` — foundation specimen cards.
- `assets/` — the 神 logo and brand imagery.

If creating visual artifacts (slides, mocks, throwaway prototypes), copy assets out and create static HTML files for the user to view. If working on production code, copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without other guidance, ask what they want to build, ask a few questions, and act as an expert designer who outputs HTML artifacts **or** production code as needed. Keep the voice terse, confident, engineering-grade, Simplified-Chinese-first with English technical nouns. No decorative emoji.
