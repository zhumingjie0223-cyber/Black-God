import React from "react";

/**
 * Black God — Card
 * The machined-metal panel: obsidian fill, hairline edge, top specular.
 * variant "chrome" adds the brand glow; "inset" is a recessed well.
 */
export function Card({
  children,
  variant = "raised",
  padding = 16,
  onClick,
  style = {},
  ...rest
}) {
  const variants = {
    raised: {
      background: "var(--bg-2)",
      border: "1px solid var(--line)",
      boxShadow: "var(--panel-chrome)",
    },
    chrome: {
      background: "linear-gradient(160deg, var(--bg-2), var(--bg-1))",
      border: "1px solid var(--line-chrome)",
      boxShadow: "var(--panel-chrome), var(--glow-chrome-sm)",
    },
    inset: {
      background: "var(--bg)",
      border: "1px solid var(--line)",
      boxShadow: "inset 0 2px 8px rgba(0,0,0,.4)",
    },
    flat: {
      background: "var(--surface)",
      border: "1px solid var(--line)",
      boxShadow: "none",
    },
  };

  return (
    <div
      onClick={onClick}
      style={{
        borderRadius: "var(--radius)",
        padding,
        cursor: onClick ? "pointer" : "default",
        transition: "border-color var(--t-fast), box-shadow var(--t-fast), transform var(--t-fast)",
        ...variants[variant],
        ...style,
      }}
      {...rest}
    >
      {children}
    </div>
  );
}
