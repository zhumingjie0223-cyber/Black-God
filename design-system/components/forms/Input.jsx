import React from "react";

/**
 * Black God — Input
 * Recessed obsidian field with chrome focus ring. Supports leading icon
 * and an optional trailing slot (e.g. send / clear).
 */
export function Input({
  value,
  onChange,
  placeholder = "",
  icon = null,
  trailing = null,
  type = "text",
  multiline = false,
  disabled = false,
  style = {},
  ...rest
}) {
  const [focused, setFocused] = React.useState(false);
  const Field = multiline ? "textarea" : "input";

  return (
    <div
      style={{
        display: "flex",
        alignItems: multiline ? "flex-end" : "center",
        gap: 10,
        minHeight: "var(--h-field)",
        padding: multiline ? "12px 14px" : "0 14px",
        background: "var(--bg)",
        border: `1px solid ${focused ? "var(--line-chrome)" : "var(--line)"}`,
        borderRadius: multiline ? "var(--radius-sm)" : "var(--radius-pill)",
        boxShadow: focused ? "var(--ring), inset 0 2px 6px rgba(0,0,0,.35)" : "inset 0 2px 6px rgba(0,0,0,.35)",
        transition: "border-color var(--t-fast), box-shadow var(--t-fast)",
        opacity: disabled ? 0.5 : 1,
        ...style,
      }}
    >
      {icon && <span style={{ color: "var(--chrome-3)", fontSize: 16, flex: "0 0 auto" }}>{icon}</span>}
      <Field
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        type={multiline ? undefined : type}
        disabled={disabled}
        rows={multiline ? 1 : undefined}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        style={{
          flex: 1,
          width: "100%",
          border: "none",
          outline: "none",
          background: "transparent",
          color: "var(--text)",
          fontFamily: "var(--font-sans)",
          fontSize: "var(--fs-body)",
          resize: "none",
          lineHeight: "var(--lh-snug)",
          padding: 0,
        }}
        {...rest}
      />
      {trailing && <span style={{ flex: "0 0 auto", display: "inline-flex" }}>{trailing}</span>}
    </div>
  );
}
