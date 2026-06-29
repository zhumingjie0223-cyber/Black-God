import React from "react";

/**
 * Black God — Badge
 * Functional state token. Semantic colors are the ONLY non-chrome color
 * allowed in the system, reserved for status: ok / run / warn / err / neutral.
 */
const TONES = {
  ok:      { c: "var(--ok)",   bg: "var(--ok-dim)",   b: "var(--ok-line)" },
  run:     { c: "var(--run)",  bg: "var(--run-dim)",  b: "var(--run-line)" },
  warn:    { c: "var(--warn)", bg: "var(--warn-dim)", b: "var(--warn-line)" },
  err:     { c: "var(--err)",  bg: "var(--err-dim)",  b: "var(--err-line)" },
  chrome:  { c: "var(--chrome-1)", bg: "var(--surface-2)", b: "var(--line-chrome)" },
  neutral: { c: "var(--text-2)", bg: "var(--surface)", b: "var(--line)" },
};

export function Badge({ children, tone = "neutral", dot = false, style = {}, ...rest }) {
  const t = TONES[tone] || TONES.neutral;
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        height: 22,
        padding: "0 9px",
        fontSize: "var(--fs-micro)",
        fontWeight: "var(--fw-semibold)",
        letterSpacing: ".03em",
        fontFamily: "var(--font-sans)",
        color: t.c,
        background: t.bg,
        border: `1px solid ${t.b}`,
        borderRadius: "var(--radius-full)",
        whiteSpace: "nowrap",
        ...style,
      }}
      {...rest}
    >
      {dot && (
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: "50%",
            background: t.c,
            boxShadow: `0 0 6px ${t.c}`,
          }}
        />
      )}
      {children}
    </span>
  );
}
