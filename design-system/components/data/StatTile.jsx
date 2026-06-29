import React from "react";

/**
 * Black God — StatTile
 * Compact metric tile for dashboards (cost saved, cache hit-rate, tokens).
 * Chrome value, muted label, optional delta in a semantic tone.
 */
export function StatTile({ label, value, unit = "", delta = null, deltaTone = "ok", icon = null, style = {} }) {
  const tones = { ok: "var(--ok)", err: "var(--err)", run: "var(--run)", neutral: "var(--text-3)" };
  return (
    <div
      style={{
        background: "var(--bg-2)",
        border: "1px solid var(--line)",
        borderRadius: "var(--radius)",
        padding: "14px 16px",
        boxShadow: "var(--panel-chrome)",
        display: "flex",
        flexDirection: "column",
        gap: 8,
        ...style,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <span style={{ fontSize: "var(--fs-micro)", letterSpacing: "var(--ls-label)", textTransform: "uppercase", color: "var(--text-3)", fontWeight: "var(--fw-semibold)" }}>
          {label}
        </span>
        {icon && <span style={{ color: "var(--chrome-3)", fontSize: 14 }}>{icon}</span>}
      </div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
        <span
          style={{
            fontSize: 26,
            fontWeight: "var(--fw-heavy)",
            letterSpacing: "var(--ls-tight)",
            background: "var(--chrome-grad)",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            backgroundClip: "text",
          }}
        >
          {value}
        </span>
        {unit && <span style={{ fontSize: 13, color: "var(--text-2)", fontWeight: "var(--fw-medium)" }}>{unit}</span>}
      </div>
      {delta != null && (
        <span style={{ fontSize: "var(--fs-cap)", color: tones[deltaTone], fontWeight: "var(--fw-semibold)" }}>
          {delta}
        </span>
      )}
    </div>
  );
}
