import React from "react";

/**
 * Black God — Button
 * Obsidian Chrome action. Primary = brushed-chrome plate with cold glow;
 * secondary = chrome-outline; ghost = bare; danger = red plate.
 */
export function Button({
  children,
  variant = "primary",
  size = "md",
  block = false,
  disabled = false,
  icon = null,
  iconRight = null,
  style = {},
  ...rest
}) {
  const sizes = {
    sm: { height: 36, padding: "0 14px", fontSize: 13, radius: "var(--radius-sm)", gap: 7 },
    md: { height: 44, padding: "0 20px", fontSize: 15, radius: "var(--radius-sm)", gap: 8 },
    lg: { height: 52, padding: "0 26px", fontSize: 16, radius: "var(--radius)", gap: 9 },
  };
  const s = sizes[size] || sizes.md;

  const base = {
    display: block ? "flex" : "inline-flex",
    width: block ? "100%" : "auto",
    alignItems: "center",
    justifyContent: "center",
    gap: s.gap,
    height: s.height,
    padding: s.padding,
    fontSize: s.fontSize,
    fontFamily: "var(--font-sans)",
    fontWeight: "var(--fw-bold)",
    letterSpacing: ".01em",
    borderRadius: s.radius,
    cursor: disabled ? "not-allowed" : "pointer",
    border: "none",
    whiteSpace: "nowrap",
    transition: "transform var(--t-fast) var(--ease-out), box-shadow var(--t-fast), filter var(--t-fast), background var(--t-fast)",
    opacity: disabled ? 0.4 : 1,
    pointerEvents: disabled ? "none" : "auto",
    filter: disabled ? "grayscale(.4)" : "none",
    ...style,
  };

  const variants = {
    primary: {
      color: "var(--bubble-user-ink)",
      background: "var(--chrome-grad-soft)",
      boxShadow: "var(--btn-lift), var(--inset-hi-2)",
    },
    secondary: {
      color: "var(--chrome-1)",
      background: "var(--surface-2)",
      border: "1px solid var(--line-chrome)",
      boxShadow: "var(--inset-hi)",
    },
    ghost: {
      color: "var(--text-2)",
      background: "transparent",
      border: "1px solid var(--line-2)",
    },
    danger: {
      color: "#2A0808",
      background: "linear-gradient(150deg,#FF8A8A,#FF6B6B)",
      boxShadow: "0 4px 16px var(--err-dim)",
    },
  };

  const [pressed, setPressed] = React.useState(false);
  const pressStyle = pressed && !disabled ? { transform: "scale(.97)", filter: "brightness(.96)" } : null;

  return (
    <button
      style={{ ...base, ...(variants[variant] || variants.primary), ...pressStyle }}
      disabled={disabled}
      onPointerDown={() => setPressed(true)}
      onPointerUp={() => setPressed(false)}
      onPointerLeave={() => setPressed(false)}
      {...rest}
    >
      {icon && <span style={{ display: "inline-flex", fontSize: "1.1em" }}>{icon}</span>}
      {children}
      {iconRight && <span style={{ display: "inline-flex", fontSize: "1.1em" }}>{iconRight}</span>}
    </button>
  );
}
