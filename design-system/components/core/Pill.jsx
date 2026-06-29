import React from "react";

/**
 * Black God — Pill
 * Status pill used for the active model selector in the top bar.
 * Shows a live status dot + label.
 */
export function Pill({ children, status = "ok", style = {}, ...rest }) {
  const dot = {
    ok: "var(--ok)",
    run: "var(--run)",
    warn: "var(--warn)",
    err: "var(--err)",
    idle: "var(--chrome-3)",
  }[status] || "var(--ok)";
  const [pressed, setPressed] = React.useState(false);
  return (
    <button
      onPointerDown={() => setPressed(true)}
      onPointerUp={() => setPressed(false)}
      onPointerLeave={() => setPressed(false)}
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 5,
        height: 30,
        padding: "0 11px",
        flexShrink: 0,
        cursor: "pointer",
        fontSize: 12,
        fontFamily: "var(--font-sans)",
        fontWeight: "var(--fw-semibold)",
        color: "var(--chrome-1)",
        background: "var(--surface-2)",
        border: "1px solid var(--line-2)",
        borderRadius: "var(--radius-pill)",
        transition: "transform var(--t-fast), background var(--t-fast)",
        transform: pressed ? "scale(.95)" : "none",
        ...style,
      }}
      {...rest}
    >
      <span style={{ width: 6, height: 6, borderRadius: "50%", background: dot, boxShadow: `0 0 6px ${dot}` }} />
      {children}
    </button>
  );
}
