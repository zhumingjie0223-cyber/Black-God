import React from "react";

/**
 * Black God — CascadeBar
 * THE signature visualization: the L0–L6 cost cascade. Each level is a
 * segment; the level a request resolved at lights up in chrome, cheaper
 * levels read as "saved", deeper levels dim. Tells the cost story at a glance.
 */
const LEVELS = [
  { id: "L0", name: "缓存",   en: "Cache" },
  { id: "L1", name: "规则",   en: "Rules" },
  { id: "L2", name: "本地工具", en: "Local" },
  { id: "L3", name: "便宜模型", en: "Cheap" },
  { id: "L4", name: "贵模型",  en: "Premium" },
  { id: "L5", name: "深度推理", en: "Reason" },
  { id: "L6", name: "人工",   en: "Human" },
];

export function CascadeBar({ resolvedAt = 2, labels = true, compact = false, style = {} }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8, ...style }}>
      <div style={{ display: "flex", gap: 4 }}>
        {LEVELS.map((lv, i) => {
          const resolved = i === resolvedAt;
          const saved = i < resolvedAt;
          return (
            <div
              key={lv.id}
              title={`${lv.id} · ${lv.name}`}
              style={{
                flex: 1,
                height: compact ? 8 : 38,
                borderRadius: "var(--radius-xs)",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                gap: 2,
                position: "relative",
                background: resolved
                  ? "var(--chrome-grad-soft)"
                  : saved
                  ? "var(--surface-2)"
                  : "var(--bg)",
                border: `1px solid ${resolved ? "var(--line-chrome)" : saved ? "var(--line)" : "var(--line)"}`,
                boxShadow: resolved ? "var(--glow-chrome-sm), var(--inset-hi-2)" : "none",
                opacity: !resolved && !saved ? 0.45 : 1,
                transition: "all var(--t-base) var(--ease-out)",
              }}
            >
              {!compact && (
                <span
                  style={{
                    fontSize: 10,
                    fontWeight: "var(--fw-bold)",
                    color: resolved ? "var(--bubble-user-ink)" : saved ? "var(--chrome-2)" : "var(--text-3)",
                    letterSpacing: ".02em",
                  }}
                >
                  {lv.id}
                </span>
              )}
            </div>
          );
        })}
      </div>
      {labels && !compact && (
        <div style={{ display: "flex", justifyContent: "space-between", padding: "0 2px" }}>
          <span style={{ fontSize: "var(--fs-micro)", color: "var(--ok)", fontWeight: "var(--fw-semibold)" }}>
            ← 越便宜 / 越快
          </span>
          <span style={{ fontSize: "var(--fs-micro)", color: "var(--text-3)", fontWeight: "var(--fw-semibold)" }}>
            越贵 / 越慢 →
          </span>
        </div>
      )}
    </div>
  );
}
