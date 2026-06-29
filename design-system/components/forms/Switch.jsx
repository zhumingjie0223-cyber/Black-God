import React from "react";

/**
 * Black God — Switch
 * iOS-style toggle, chrome track when on. Used for privacy guardrails,
 * local-first toggles, provider enable.
 */
export function Switch({ checked = false, onChange, disabled = false, style = {} }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      onClick={() => !disabled && onChange && onChange(!checked)}
      style={{
        position: "relative",
        width: 46,
        height: 28,
        flex: "0 0 auto",
        borderRadius: "var(--radius-full)",
        border: "1px solid",
        borderColor: checked ? "var(--line-chrome)" : "var(--line-2)",
        background: checked ? "var(--chrome-grad-soft)" : "var(--bg-3)",
        boxShadow: checked ? "var(--inset-hi-2)" : "inset 0 1px 3px rgba(0,0,0,.4)",
        cursor: disabled ? "not-allowed" : "pointer",
        opacity: disabled ? 0.4 : 1,
        transition: "background var(--t-base) var(--ease-out), border-color var(--t-base)",
        padding: 0,
        ...style,
      }}
    >
      <span
        style={{
          position: "absolute",
          top: 2,
          left: checked ? 20 : 2,
          width: 22,
          height: 22,
          borderRadius: "var(--radius-full)",
          background: checked ? "#1A1C20" : "#E8EBEF",
          boxShadow: "0 2px 5px rgba(0,0,0,.45)",
          transition: "left var(--t-base) var(--ease-spring)",
        }}
      />
    </button>
  );
}
