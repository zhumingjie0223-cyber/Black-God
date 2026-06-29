import React from "react";

/**
 * Black God — IconButton
 * Circular/rounded chrome control for toolbars, composers, sheet headers.
 */
export function IconButton({
  children,
  variant = "soft",
  size = "md",
  round = true,
  active = false,
  disabled = false,
  style = {},
  ...rest
}) {
  const sizes = { sm: 30, md: 34, lg: 44 };
  const dim = sizes[size] || sizes.md;

  const variants = {
    soft: {
      color: active ? "var(--chrome-hi)" : "var(--chrome-2)",
      background: active ? "var(--surface-3)" : "var(--surface)",
      border: "1px solid var(--line)",
    },
    chrome: {
      color: "var(--bubble-user-ink)",
      background: "var(--chrome-grad-soft)",
      border: "none",
      boxShadow: "var(--inset-hi-2)",
    },
    bare: {
      color: active ? "var(--chrome-hi)" : "var(--chrome-3)",
      background: "transparent",
      border: "none",
    },
  };

  const [pressed, setPressed] = React.useState(false);

  return (
    <button
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        width: dim,
        height: dim,
        fontSize: dim * 0.46,
        borderRadius: round ? "var(--radius-full)" : "var(--radius-xs)",
        cursor: disabled ? "not-allowed" : "pointer",
        opacity: disabled ? 0.4 : 1,
        pointerEvents: disabled ? "none" : "auto",
        transition: "transform var(--t-fast) var(--ease-out), background var(--t-fast), color var(--t-fast)",
        transform: pressed && !disabled ? "scale(.9)" : "none",
        ...variants[variant],
        ...style,
      }}
      disabled={disabled}
      onPointerDown={() => setPressed(true)}
      onPointerUp={() => setPressed(false)}
      onPointerLeave={() => setPressed(false)}
      {...rest}
    >
      {children}
    </button>
  );
}
