import React from "react";

/**
 * Black God — Chip
 * Capability pill / filter token. Used for the welcome-screen capability
 * row (本地优先 · 不锁平台 · 真执行) and selectable filters.
 */
export function Chip({
  children,
  selected = false,
  icon = null,
  size = "md",
  onClick,
  style = {},
  ...rest
}) {
  const pad = size === "sm" ? "0 11px" : "0 14px";
  const h = size === "sm" ? 26 : "var(--h-chip)";
  const interactive = !!onClick;

  return (
    <button
      onClick={onClick}
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        height: h,
        padding: pad,
        fontSize: size === "sm" ? 12 : 13,
        fontWeight: "var(--fw-medium)",
        fontFamily: "var(--font-sans)",
        color: selected ? "var(--chrome-hi)" : "var(--chrome-2)",
        background: selected ? "var(--surface-3)" : "var(--surface)",
        border: `1px solid ${selected ? "var(--line-chrome)" : "var(--line)"}`,
        borderRadius: "var(--radius-pill)",
        cursor: interactive ? "pointer" : "default",
        whiteSpace: "nowrap",
        boxShadow: selected ? "var(--inset-hi)" : "none",
        transition: "color var(--t-fast), background var(--t-fast), border-color var(--t-fast)",
        ...style,
      }}
      {...rest}
    >
      {icon && <span style={{ opacity: 0.9 }}>{icon}</span>}
      {children}
    </button>
  );
}
