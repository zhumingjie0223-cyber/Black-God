import React from "react";

/**
 * Black God — Avatar
 * The metallic "神" mark for the assistant; chrome initial plate for the user.
 */
export function Avatar({ src, label = "", size = 36, kind = "user", style = {} }) {
  const isGod = kind === "god";
  return (
    <div
      style={{
        width: size,
        height: size,
        flex: "0 0 auto",
        borderRadius: "var(--radius-full)",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        overflow: "hidden",
        fontFamily: "var(--font-sans)",
        fontWeight: "var(--fw-bold)",
        fontSize: size * 0.42,
        color: "var(--bubble-user-ink)",
        background: isGod ? "#0A0B0E" : "var(--chrome-grad-soft)",
        border: isGod ? "1px solid var(--line-chrome)" : "none",
        boxShadow: isGod ? "var(--glow-chrome-sm), var(--inset-hi)" : "var(--inset-hi-2)",
        ...style,
      }}
    >
      {src ? (
        <img src={src} alt={label} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
      ) : (
        <span>{label.slice(0, 1).toUpperCase() || "U"}</span>
      )}
    </div>
  );
}
