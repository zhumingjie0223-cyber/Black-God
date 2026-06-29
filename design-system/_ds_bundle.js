/* @ds-bundle: {"format":3,"namespace":"BlackGodDesignSystem_7a1b36","components":[{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Card","sourcePath":"components/core/Card.jsx"},{"name":"Chip","sourcePath":"components/core/Chip.jsx"},{"name":"IconButton","sourcePath":"components/core/IconButton.jsx"},{"name":"Pill","sourcePath":"components/core/Pill.jsx"},{"name":"Avatar","sourcePath":"components/data/Avatar.jsx"},{"name":"Badge","sourcePath":"components/data/Badge.jsx"},{"name":"CascadeBar","sourcePath":"components/data/CascadeBar.jsx"},{"name":"StatTile","sourcePath":"components/data/StatTile.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"Switch","sourcePath":"components/forms/Switch.jsx"}],"sourceHashes":{"components/core/Button.jsx":"056c5317311a","components/core/Card.jsx":"773105ff19ff","components/core/Chip.jsx":"a73817599b5e","components/core/IconButton.jsx":"d9badde8af0d","components/core/Pill.jsx":"152d7fbc8d90","components/data/Avatar.jsx":"4585bca89deb","components/data/Badge.jsx":"4df73aecf893","components/data/CascadeBar.jsx":"51861c00dbbb","components/data/StatTile.jsx":"2259ce3a221c","components/forms/Input.jsx":"ce1c5b650936","components/forms/Switch.jsx":"27e7e26eea86","ui_kits/app/ChatScreen.jsx":"5742bb792654","ui_kits/app/ProfileScreen.jsx":"d22500310d59","ui_kits/app/ProviderSheet.jsx":"da27c12aeb6c","ui_kits/app/RecordsScreen.jsx":"b4aa537910e2"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.BlackGodDesignSystem_7a1b36 = window.BlackGodDesignSystem_7a1b36 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Black God — Button
 * Obsidian Chrome action. Primary = brushed-chrome plate with cold glow;
 * secondary = chrome-outline; ghost = bare; danger = red plate.
 */
function Button({
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
    sm: {
      height: 36,
      padding: "0 14px",
      fontSize: 13,
      radius: "var(--radius-sm)",
      gap: 7
    },
    md: {
      height: 44,
      padding: "0 20px",
      fontSize: 15,
      radius: "var(--radius-sm)",
      gap: 8
    },
    lg: {
      height: 52,
      padding: "0 26px",
      fontSize: 16,
      radius: "var(--radius)",
      gap: 9
    }
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
    ...style
  };
  const variants = {
    primary: {
      color: "var(--bubble-user-ink)",
      background: "var(--chrome-grad-soft)",
      boxShadow: "var(--btn-lift), var(--inset-hi-2)"
    },
    secondary: {
      color: "var(--chrome-1)",
      background: "var(--surface-2)",
      border: "1px solid var(--line-chrome)",
      boxShadow: "var(--inset-hi)"
    },
    ghost: {
      color: "var(--text-2)",
      background: "transparent",
      border: "1px solid var(--line-2)"
    },
    danger: {
      color: "#2A0808",
      background: "linear-gradient(150deg,#FF8A8A,#FF6B6B)",
      boxShadow: "0 4px 16px var(--err-dim)"
    }
  };
  const [pressed, setPressed] = React.useState(false);
  const pressStyle = pressed && !disabled ? {
    transform: "scale(.97)",
    filter: "brightness(.96)"
  } : null;
  return /*#__PURE__*/React.createElement("button", _extends({
    style: {
      ...base,
      ...(variants[variant] || variants.primary),
      ...pressStyle
    },
    disabled: disabled,
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false)
  }, rest), icon && /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      fontSize: "1.1em"
    }
  }, icon), children, iconRight && /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      fontSize: "1.1em"
    }
  }, iconRight));
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Black God — Card
 * The machined-metal panel: obsidian fill, hairline edge, top specular.
 * variant "chrome" adds the brand glow; "inset" is a recessed well.
 */
function Card({
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
      boxShadow: "var(--panel-chrome)"
    },
    chrome: {
      background: "linear-gradient(160deg, var(--bg-2), var(--bg-1))",
      border: "1px solid var(--line-chrome)",
      boxShadow: "var(--panel-chrome), var(--glow-chrome-sm)"
    },
    inset: {
      background: "var(--bg)",
      border: "1px solid var(--line)",
      boxShadow: "inset 0 2px 8px rgba(0,0,0,.4)"
    },
    flat: {
      background: "var(--surface)",
      border: "1px solid var(--line)",
      boxShadow: "none"
    }
  };
  return /*#__PURE__*/React.createElement("div", _extends({
    onClick: onClick,
    style: {
      borderRadius: "var(--radius)",
      padding,
      cursor: onClick ? "pointer" : "default",
      transition: "border-color var(--t-fast), box-shadow var(--t-fast), transform var(--t-fast)",
      ...variants[variant],
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Card.jsx", error: String((e && e.message) || e) }); }

// components/core/Chip.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Black God — Chip
 * Capability pill / filter token. Used for the welcome-screen capability
 * row (本地优先 · 不锁平台 · 真执行) and selectable filters.
 */
function Chip({
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
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    style: {
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
      ...style
    }
  }, rest), icon && /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: 0.9
    }
  }, icon), children);
}
Object.assign(__ds_scope, { Chip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Chip.jsx", error: String((e && e.message) || e) }); }

// components/core/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Black God — IconButton
 * Circular/rounded chrome control for toolbars, composers, sheet headers.
 */
function IconButton({
  children,
  variant = "soft",
  size = "md",
  round = true,
  active = false,
  disabled = false,
  style = {},
  ...rest
}) {
  const sizes = {
    sm: 30,
    md: 34,
    lg: 44
  };
  const dim = sizes[size] || sizes.md;
  const variants = {
    soft: {
      color: active ? "var(--chrome-hi)" : "var(--chrome-2)",
      background: active ? "var(--surface-3)" : "var(--surface)",
      border: "1px solid var(--line)"
    },
    chrome: {
      color: "var(--bubble-user-ink)",
      background: "var(--chrome-grad-soft)",
      border: "none",
      boxShadow: "var(--inset-hi-2)"
    },
    bare: {
      color: active ? "var(--chrome-hi)" : "var(--chrome-3)",
      background: "transparent",
      border: "none"
    }
  };
  const [pressed, setPressed] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", _extends({
    style: {
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
      ...style
    },
    disabled: disabled,
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false)
  }, rest), children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/core/Pill.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Black God — Pill
 * Status pill used for the active model selector in the top bar.
 * Shows a live status dot + label.
 */
function Pill({
  children,
  status = "ok",
  style = {},
  ...rest
}) {
  const dot = {
    ok: "var(--ok)",
    run: "var(--run)",
    warn: "var(--warn)",
    err: "var(--err)",
    idle: "var(--chrome-3)"
  }[status] || "var(--ok)";
  const [pressed, setPressed] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", _extends({
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false),
    style: {
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
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 6,
      height: 6,
      borderRadius: "50%",
      background: dot,
      boxShadow: `0 0 6px ${dot}`
    }
  }), children);
}
Object.assign(__ds_scope, { Pill });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Pill.jsx", error: String((e && e.message) || e) }); }

// components/data/Avatar.jsx
try { (() => {
/**
 * Black God — Avatar
 * The metallic "神" mark for the assistant; chrome initial plate for the user.
 */
function Avatar({
  src,
  label = "",
  size = 36,
  kind = "user",
  style = {}
}) {
  const isGod = kind === "god";
  return /*#__PURE__*/React.createElement("div", {
    style: {
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
      ...style
    }
  }, src ? /*#__PURE__*/React.createElement("img", {
    src: src,
    alt: label,
    style: {
      width: "100%",
      height: "100%",
      objectFit: "cover"
    }
  }) : /*#__PURE__*/React.createElement("span", null, label.slice(0, 1).toUpperCase() || "U"));
}
Object.assign(__ds_scope, { Avatar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/Avatar.jsx", error: String((e && e.message) || e) }); }

// components/data/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Black God — Badge
 * Functional state token. Semantic colors are the ONLY non-chrome color
 * allowed in the system, reserved for status: ok / run / warn / err / neutral.
 */
const TONES = {
  ok: {
    c: "var(--ok)",
    bg: "var(--ok-dim)",
    b: "var(--ok-line)"
  },
  run: {
    c: "var(--run)",
    bg: "var(--run-dim)",
    b: "var(--run-line)"
  },
  warn: {
    c: "var(--warn)",
    bg: "var(--warn-dim)",
    b: "var(--warn-line)"
  },
  err: {
    c: "var(--err)",
    bg: "var(--err-dim)",
    b: "var(--err-line)"
  },
  chrome: {
    c: "var(--chrome-1)",
    bg: "var(--surface-2)",
    b: "var(--line-chrome)"
  },
  neutral: {
    c: "var(--text-2)",
    bg: "var(--surface)",
    b: "var(--line)"
  }
};
function Badge({
  children,
  tone = "neutral",
  dot = false,
  style = {},
  ...rest
}) {
  const t = TONES[tone] || TONES.neutral;
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
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
      ...style
    }
  }, rest), dot && /*#__PURE__*/React.createElement("span", {
    style: {
      width: 6,
      height: 6,
      borderRadius: "50%",
      background: t.c,
      boxShadow: `0 0 6px ${t.c}`
    }
  }), children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/Badge.jsx", error: String((e && e.message) || e) }); }

// components/data/CascadeBar.jsx
try { (() => {
/**
 * Black God — CascadeBar
 * THE signature visualization: the L0–L6 cost cascade. Each level is a
 * segment; the level a request resolved at lights up in chrome, cheaper
 * levels read as "saved", deeper levels dim. Tells the cost story at a glance.
 */
const LEVELS = [{
  id: "L0",
  name: "缓存",
  en: "Cache"
}, {
  id: "L1",
  name: "规则",
  en: "Rules"
}, {
  id: "L2",
  name: "本地工具",
  en: "Local"
}, {
  id: "L3",
  name: "便宜模型",
  en: "Cheap"
}, {
  id: "L4",
  name: "贵模型",
  en: "Premium"
}, {
  id: "L5",
  name: "深度推理",
  en: "Reason"
}, {
  id: "L6",
  name: "人工",
  en: "Human"
}];
function CascadeBar({
  resolvedAt = 2,
  labels = true,
  compact = false,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 8,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 4
    }
  }, LEVELS.map((lv, i) => {
    const resolved = i === resolvedAt;
    const saved = i < resolvedAt;
    return /*#__PURE__*/React.createElement("div", {
      key: lv.id,
      title: `${lv.id} · ${lv.name}`,
      style: {
        flex: 1,
        height: compact ? 8 : 38,
        borderRadius: "var(--radius-xs)",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 2,
        position: "relative",
        background: resolved ? "var(--chrome-grad-soft)" : saved ? "var(--surface-2)" : "var(--bg)",
        border: `1px solid ${resolved ? "var(--line-chrome)" : saved ? "var(--line)" : "var(--line)"}`,
        boxShadow: resolved ? "var(--glow-chrome-sm), var(--inset-hi-2)" : "none",
        opacity: !resolved && !saved ? 0.45 : 1,
        transition: "all var(--t-base) var(--ease-out)"
      }
    }, !compact && /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 10,
        fontWeight: "var(--fw-bold)",
        color: resolved ? "var(--bubble-user-ink)" : saved ? "var(--chrome-2)" : "var(--text-3)",
        letterSpacing: ".02em"
      }
    }, lv.id));
  })), labels && !compact && /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "space-between",
      padding: "0 2px"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--fs-micro)",
      color: "var(--ok)",
      fontWeight: "var(--fw-semibold)"
    }
  }, "\u2190 \u8D8A\u4FBF\u5B9C / \u8D8A\u5FEB"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--fs-micro)",
      color: "var(--text-3)",
      fontWeight: "var(--fw-semibold)"
    }
  }, "\u8D8A\u8D35 / \u8D8A\u6162 \u2192")));
}
Object.assign(__ds_scope, { CascadeBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/CascadeBar.jsx", error: String((e && e.message) || e) }); }

// components/data/StatTile.jsx
try { (() => {
/**
 * Black God — StatTile
 * Compact metric tile for dashboards (cost saved, cache hit-rate, tokens).
 * Chrome value, muted label, optional delta in a semantic tone.
 */
function StatTile({
  label,
  value,
  unit = "",
  delta = null,
  deltaTone = "ok",
  icon = null,
  style = {}
}) {
  const tones = {
    ok: "var(--ok)",
    err: "var(--err)",
    run: "var(--run)",
    neutral: "var(--text-3)"
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: "var(--bg-2)",
      border: "1px solid var(--line)",
      borderRadius: "var(--radius)",
      padding: "14px 16px",
      boxShadow: "var(--panel-chrome)",
      display: "flex",
      flexDirection: "column",
      gap: 8,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--fs-micro)",
      letterSpacing: "var(--ls-label)",
      textTransform: "uppercase",
      color: "var(--text-3)",
      fontWeight: "var(--fw-semibold)"
    }
  }, label), icon && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--chrome-3)",
      fontSize: 14
    }
  }, icon)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "baseline",
      gap: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 26,
      fontWeight: "var(--fw-heavy)",
      letterSpacing: "var(--ls-tight)",
      background: "var(--chrome-grad)",
      WebkitBackgroundClip: "text",
      WebkitTextFillColor: "transparent",
      backgroundClip: "text"
    }
  }, value), unit && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 13,
      color: "var(--text-2)",
      fontWeight: "var(--fw-medium)"
    }
  }, unit)), delta != null && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--fs-cap)",
      color: tones[deltaTone],
      fontWeight: "var(--fw-semibold)"
    }
  }, delta));
}
Object.assign(__ds_scope, { StatTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/StatTile.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Black God — Input
 * Recessed obsidian field with chrome focus ring. Supports leading icon
 * and an optional trailing slot (e.g. send / clear).
 */
function Input({
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
  return /*#__PURE__*/React.createElement("div", {
    style: {
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
      ...style
    }
  }, icon && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--chrome-3)",
      fontSize: 16,
      flex: "0 0 auto"
    }
  }, icon), /*#__PURE__*/React.createElement(Field, _extends({
    value: value,
    onChange: onChange,
    placeholder: placeholder,
    type: multiline ? undefined : type,
    disabled: disabled,
    rows: multiline ? 1 : undefined,
    onFocus: () => setFocused(true),
    onBlur: () => setFocused(false),
    style: {
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
      padding: 0
    }
  }, rest)), trailing && /*#__PURE__*/React.createElement("span", {
    style: {
      flex: "0 0 auto",
      display: "inline-flex"
    }
  }, trailing));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/Switch.jsx
try { (() => {
/**
 * Black God — Switch
 * iOS-style toggle, chrome track when on. Used for privacy guardrails,
 * local-first toggles, provider enable.
 */
function Switch({
  checked = false,
  onChange,
  disabled = false,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("button", {
    role: "switch",
    "aria-checked": checked,
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
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
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: 2,
      left: checked ? 20 : 2,
      width: 22,
      height: 22,
      borderRadius: "var(--radius-full)",
      background: checked ? "#1A1C20" : "#E8EBEF",
      boxShadow: "0 2px 5px rgba(0,0,0,.45)",
      transition: "left var(--t-base) var(--ease-spring)"
    }
  }));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Switch.jsx", error: String((e && e.message) || e) }); }

// ui_kits/app/ChatScreen.jsx
try { (() => {
// Black God App — Chat screen. The execution hub: messages, a tool/cascade
// trace, the consent prompt, and the chrome composer. Reuses DS primitives.
const {
  Avatar,
  Badge,
  CascadeBar,
  Card,
  IconButton,
  Input,
  Button
} = window.BlackGodDesignSystem_7a1b36;
function ToolTrace({
  steps
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 6,
      margin: "4px 0 2px"
    }
  }, steps.map((s, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      fontSize: 13,
      color: "var(--text-2)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 16,
      textAlign: "center",
      color: s.tone === "ok" ? "var(--ok)" : s.tone === "run" ? "var(--run)" : "var(--chrome-3)"
    }
  }, s.tone === "ok" ? "✓" : s.tone === "run" ? "◐" : "·"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: 12.5,
      color: "var(--chrome-2)"
    }
  }, s.tool), /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--text-3)"
    }
  }, s.note))));
}
function GodMessage({
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 10,
      alignItems: "flex-start"
    }
  }, /*#__PURE__*/React.createElement(Avatar, {
    kind: "god",
    src: "../../assets/logo-god.png",
    size: 34
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, children));
}
function UserMessage({
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "flex-end"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: "78%",
      padding: "10px 14px",
      borderRadius: "16px 16px 4px 16px",
      background: "var(--bubble-user)",
      color: "var(--bubble-user-ink)",
      fontSize: "var(--fs-body)",
      fontWeight: 500,
      lineHeight: "var(--lh-snug)",
      boxShadow: "var(--inset-hi-2)"
    }
  }, children));
}
function ChatScreen({
  onOpenProvider
}) {
  const [text, setText] = React.useState("");
  const [consented, setConsented] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      height: "100%",
      background: "var(--field-bg)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      padding: "14px 16px",
      background: "rgba(10,11,14,.7)",
      backdropFilter: "var(--blur-bar)",
      borderBottom: "1px solid var(--line)",
      flex: "0 0 auto"
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-god.png",
    style: {
      width: 28,
      height: 28,
      filter: "drop-shadow(0 2px 8px var(--chrome-glow))"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      lineHeight: 1.2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 15,
      fontWeight: 700,
      letterSpacing: ".08em",
      background: "var(--chrome-grad)",
      WebkitBackgroundClip: "text",
      backgroundClip: "text",
      WebkitTextFillColor: "transparent"
    }
  }, "BLACK GOD"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 11,
      color: "var(--text-3)"
    }
  }, "\u672C\u5730\u4F18\u5148 \xB7 \u79C1\u4EBA\u6267\u884C\u4E2D\u67A2")), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("button", {
    onClick: onOpenProvider,
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 6,
      height: 30,
      padding: "0 11px",
      borderRadius: "var(--radius-pill)",
      background: "var(--surface)",
      border: "1px solid var(--line-chrome)",
      color: "var(--chrome-1)",
      fontSize: 12.5,
      fontWeight: 500,
      cursor: "pointer",
      fontFamily: "var(--font-sans)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 7,
      height: 7,
      borderRadius: "50%",
      background: "var(--ok)",
      boxShadow: "0 0 6px var(--ok)"
    }
  }), "DeepSeek")), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflowY: "auto",
      padding: "18px 16px",
      display: "flex",
      flexDirection: "column",
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(UserMessage, null, "\u5E2E\u6211\u628A\u751F\u4EA7\u670D\u52A1\u5668\u7684 nginx \u65E5\u5FD7\u62C9\u4E0B\u6765\uFF0C\u770B\u770B\u6628\u665A 502 \u662F\u600E\u4E48\u56DE\u4E8B"), /*#__PURE__*/React.createElement(GodMessage, null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--fs-body)",
      color: "var(--text)",
      lineHeight: "var(--lh-body)",
      marginBottom: 8
    }
  }, "\u8BB0\u5F97\u4F60\u7684 ", /*#__PURE__*/React.createElement("b", {
    style: {
      color: "var(--chrome-1)"
    }
  }, "prod-sg"), " \u670D\u52A1\u5668\uFF08\u4F60\u8BBE\u8FC7\u7981\u533A\uFF1A\u4E0D\u78B0\u6570\u636E\u5E93\uFF09\u3002\u6211\u5148\u53EA\u8BFB\u65E5\u5FD7\uFF1A"), /*#__PURE__*/React.createElement(Card, {
    variant: "inset",
    padding: 12,
    style: {
      marginBottom: 8
    }
  }, /*#__PURE__*/React.createElement(ToolTrace, {
    steps: [{
      tool: "ssh.run",
      note: "tail -n 2000 /var/log/nginx/error.log",
      tone: "ok"
    }, {
      tool: "grep",
      note: "502 · 命中 47 行 · 22:14–22:31",
      tone: "ok"
    }, {
      tool: "analyze",
      note: "upstream timeout · php-fpm 队列打满",
      tone: "ok"
    }]
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--fs-body)",
      color: "var(--text)",
      lineHeight: "var(--lh-body)"
    }
  }, "\u6839\u56E0\uFF1A", /*#__PURE__*/React.createElement("b", {
    style: {
      color: "var(--chrome-1)"
    }
  }, "php-fpm"), " \u5728 22:14 \u961F\u5217\u6253\u6EE1\uFF0Cupstream \u8D85\u65F6\u3002\u5EFA\u8BAE\u628A ", /*#__PURE__*/React.createElement("code", {
    style: {
      fontFamily: "var(--font-mono)",
      color: "var(--warn)"
    }
  }, "pm.max_children"), " \u4ECE 16 \u8C03\u5230 32\u3002"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      marginTop: 10
    }
  }, /*#__PURE__*/React.createElement(Badge, {
    tone: "ok",
    dot: true
  }, "L2 \u672C\u5730\u5DE5\u5177"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: 12,
      color: "var(--text-3)"
    }
  }, "\xA50.0008 \xB7 1.4s \xB7 \u672A\u4E0A\u4E91"))), !consented ? /*#__PURE__*/React.createElement(GodMessage, null, /*#__PURE__*/React.createElement(Card, {
    variant: "chrome",
    padding: 14
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13.5,
      color: "var(--chrome-1)",
      fontWeight: 600,
      marginBottom: 4
    }
  }, "\u9700\u8981\u4F60\u6279\u51C6\u4E00\u6B21\u5199\u64CD\u4F5C"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13.5,
      color: "var(--text-2)",
      lineHeight: "var(--lh-snug)",
      marginBottom: 12
    }
  }, "\u6539 ", /*#__PURE__*/React.createElement("code", {
    style: {
      fontFamily: "var(--font-mono)",
      color: "var(--chrome-1)"
    }
  }, "php-fpm.conf"), " \u5E76 reload \u2014 \u4F1A\u5199\u5165\u670D\u52A1\u5668\u3002\u6211\u4E0D\u4F1A\u52A8\u6570\u636E\u5E93\u3002"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "sm",
    onClick: () => setConsented(true)
  }, "\u5141\u8BB8\u6267\u884C"), /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "sm"
  }, "\u4EC5\u9884\u89C8 diff")))) : /*#__PURE__*/React.createElement(GodMessage, null, /*#__PURE__*/React.createElement(Card, {
    variant: "inset",
    padding: 12
  }, /*#__PURE__*/React.createElement(ToolTrace, {
    steps: [{
      tool: "edit",
      note: "pm.max_children 16 → 32",
      tone: "ok"
    }, {
      tool: "ssh.run",
      note: "systemctl reload php-fpm",
      tone: "ok"
    }, {
      tool: "verify",
      note: "502 归零 · 压测 200rps 通过",
      tone: "ok"
    }, {
      tool: "memory.write",
      note: "记住 prod-sg 调优记录",
      tone: "ok"
    }]
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      marginTop: 10
    }
  }, /*#__PURE__*/React.createElement(Badge, {
    tone: "ok",
    dot: true
  }, "\u95ED\u73AF\u5B8C\u6210"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-mono)",
      fontSize: 12,
      color: "var(--text-3)"
    }
  }, "\u5DF2\u6C89\u6DC0\u6280\u80FD \xB7 nginx-502-triage")))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "10px 14px calc(10px + var(--safe-bot))",
      borderTop: "1px solid var(--line)",
      background: "rgba(10,11,14,.7)",
      backdropFilter: "var(--blur-bar)",
      flex: "0 0 auto"
    }
  }, /*#__PURE__*/React.createElement(Input, {
    multiline: true,
    placeholder: "\u53D1\u6D88\u606F\u7ED9 Black God\u2026",
    value: text,
    onChange: e => setText(e.target.value),
    icon: "\uFF0B",
    trailing: /*#__PURE__*/React.createElement(IconButton, {
      variant: "chrome",
      size: "md"
    }, "\u2191")
  })));
}
window.ChatScreen = ChatScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/app/ChatScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/app/ProfileScreen.jsx
try { (() => {
// Black God App — Profile / settings. Identity, privacy guardrails, the
// brand mark. Where "data stays in your hands" is made concrete.
const {
  Avatar,
  Card,
  Switch,
  Badge,
  Button,
  IconButton
} = window.BlackGodDesignSystem_7a1b36;
function SettingRow({
  icon,
  title,
  sub,
  control
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "13px 14px",
      background: "var(--bg-2)",
      border: "1px solid var(--line)",
      borderRadius: "var(--radius-sm)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 32,
      height: 32,
      flex: "0 0 auto",
      borderRadius: "var(--radius-xs)",
      background: "var(--surface-2)",
      border: "1px solid var(--line)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 15
    }
  }, icon), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 14.5,
      color: "var(--text)",
      fontWeight: 600
    }
  }, title), sub && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      color: "var(--text-3)"
    }
  }, sub)), control);
}
function ProfileScreen({
  onOpenProvider
}) {
  const [localFirst, setLocalFirst] = React.useState(true);
  const [pii, setPii] = React.useState(true);
  const [audit, setAudit] = React.useState(true);
  const [cloud, setCloud] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: "100%",
      overflowY: "auto",
      background: "var(--field-bg)",
      padding: "26px 16px calc(20px + var(--safe-bot))"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 10,
      marginBottom: 22
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-god.png",
    style: {
      width: 76,
      height: 76,
      filter: "drop-shadow(0 6px 24px var(--chrome-glow))"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 20,
      fontWeight: 700,
      color: "var(--text)"
    }
  }, "\u6797 \xB7 \u4F60\u7684\u79C1\u4EBA\u6267\u884C\u4E2D\u67A2"), /*#__PURE__*/React.createElement(Badge, {
    tone: "chrome"
  }, "\u672C\u5730\u4F18\u5148 \xB7 \u6570\u636E\u5728\u4F60\u624B\u91CC")), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      letterSpacing: "var(--ls-label)",
      textTransform: "uppercase",
      color: "var(--text-3)",
      fontWeight: 600,
      marginBottom: 10
    }
  }, "\u9690\u79C1\u62A4\u680F"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 8,
      marginBottom: 20
    }
  }, /*#__PURE__*/React.createElement(SettingRow, {
    icon: "\uD83D\uDD12",
    title: "\u672C\u5730\u4F18\u5148\u5B58\u50A8",
    sub: "\u5BC6\u7801 \xB7 \u914D\u7F6E \xB7 \u8BB0\u5FC6\u9ED8\u8BA4\u672C\u5730",
    control: /*#__PURE__*/React.createElement(Switch, {
      checked: localFirst,
      onChange: setLocalFirst
    })
  }), /*#__PURE__*/React.createElement(SettingRow, {
    icon: "\uD83D\uDEE1",
    title: "PII \u68C0\u6D4B",
    sub: "\u53D1\u9001\u524D\u81EA\u52A8\u8BC6\u522B\u5E76\u8131\u654F",
    control: /*#__PURE__*/React.createElement(Switch, {
      checked: pii,
      onChange: setPii
    })
  }), /*#__PURE__*/React.createElement(SettingRow, {
    icon: "\uD83D\uDCCB",
    title: "\u5BA1\u8BA1\u65E5\u5FD7",
    sub: "\u6BCF\u6B21\u5DE5\u5177\u8C03\u7528\u53EF\u56DE\u6EAF",
    control: /*#__PURE__*/React.createElement(Switch, {
      checked: audit,
      onChange: setAudit
    })
  }), /*#__PURE__*/React.createElement(SettingRow, {
    icon: "\u2601\uFE0F",
    title: "\u540C\u6B65\u5230\u4E91\u7AEF",
    sub: "\u9ED8\u8BA4\u5173\u95ED \xB7 \u4F60\u6765\u51B3\u5B9A",
    control: /*#__PURE__*/React.createElement(Switch, {
      checked: cloud,
      onChange: setCloud
    })
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      letterSpacing: "var(--ls-label)",
      textTransform: "uppercase",
      color: "var(--text-3)",
      fontWeight: 600,
      marginBottom: 10
    }
  }, "\u63A5\u5165"), /*#__PURE__*/React.createElement(Card, {
    variant: "raised",
    padding: 14,
    style: {
      marginBottom: 12,
      display: "flex",
      alignItems: "center",
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 14.5,
      color: "var(--text)",
      fontWeight: 600
    }
  }, "Provider Hub"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12.5,
      color: "var(--text-3)"
    }
  }, "4 \u4E2A\u5DF2\u63A5\u5165 \xB7 DeepSeek \u9ED8\u8BA4")), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "sm",
    onClick: onOpenProvider,
    icon: "\uD83D\uDD0C"
  }, "\u7BA1\u7406")), /*#__PURE__*/React.createElement(Button, {
    variant: "danger",
    size: "md",
    block: true,
    icon: "\uD83D\uDDD1",
    style: {
      marginTop: 8
    }
  }, "\u6E05\u9664\u5168\u90E8\u672C\u5730\u8BB0\u5FC6"));
}
window.ProfileScreen = ProfileScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/app/ProfileScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/app/ProviderSheet.jsx
try { (() => {
// Black God App — Provider Hub bottom sheet. Bring-your-own model gateway.
const {
  Card,
  Switch,
  Badge,
  Button,
  IconButton
} = window.BlackGodDesignSystem_7a1b36;
function ProviderRow({
  name,
  model,
  status,
  on,
  onToggle,
  local
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "13px 14px",
      background: "var(--bg-2)",
      border: `1px solid ${on ? "var(--line-chrome)" : "var(--line)"}`,
      borderRadius: "var(--radius-sm)",
      boxShadow: on ? "var(--panel-chrome), var(--glow-chrome-sm)" : "none",
      transition: "all var(--t-base) var(--ease-out)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 15,
      color: "var(--text)",
      fontWeight: 600
    }
  }, name), local && /*#__PURE__*/React.createElement(Badge, {
    tone: "ok"
  }, "\u672C\u5730")), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12.5,
      color: "var(--text-3)",
      fontFamily: "var(--font-mono)",
      marginTop: 2
    }
  }, model)), /*#__PURE__*/React.createElement(Switch, {
    checked: on,
    onChange: onToggle
  }));
}
function ProviderSheet({
  open,
  onClose
}) {
  const [providers, setProviders] = React.useState({
    deepseek: true,
    anthropic: true,
    openai: false,
    local: true
  });
  const toggle = k => setProviders(p => ({
    ...p,
    [k]: !p[k]
  }));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: 0,
      zIndex: 20,
      pointerEvents: open ? "auto" : "none"
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: onClose,
    style: {
      position: "absolute",
      inset: 0,
      background: "rgba(0,0,0,.55)",
      opacity: open ? 1 : 0,
      transition: "opacity var(--t-base)",
      backdropFilter: open ? "var(--blur-soft)" : "none"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      bottom: 0,
      transform: open ? "translateY(0)" : "translateY(100%)",
      transition: "transform var(--t-slow) var(--ease-sheet)",
      background: "var(--bg-1)",
      borderTop: "1px solid var(--line-chrome)",
      borderRadius: "22px 22px 0 0",
      padding: "10px 16px calc(20px + var(--safe-bot))",
      boxShadow: "var(--shadow-xl)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 40,
      height: 4,
      borderRadius: 99,
      background: "var(--line-2)",
      margin: "0 auto 14px"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      marginBottom: 4
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--fs-h2)",
      fontWeight: 700,
      color: "var(--text)"
    }
  }, "Provider Hub"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: "var(--text-3)"
    }
  }, "\u81EA\u5DF1\u63A5\u5165\u6A21\u578B \xB7 \u4E0D\u88AB\u5355\u4E00\u5382\u5546\u7ED1\u67B6")), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(IconButton, {
    variant: "soft",
    onClick: onClose
  }, "\u2715")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 9,
      margin: "16px 0 14px"
    }
  }, /*#__PURE__*/React.createElement(ProviderRow, {
    name: "DeepSeek",
    model: "deepseek-chat \xB7 L3 \u9ED8\u8BA4",
    on: providers.deepseek,
    onToggle: () => toggle("deepseek")
  }), /*#__PURE__*/React.createElement(ProviderRow, {
    name: "Anthropic",
    model: "claude \xB7 L4 \u5347\u7EA7\u8DEF\u5F84",
    on: providers.anthropic,
    onToggle: () => toggle("anthropic")
  }), /*#__PURE__*/React.createElement(ProviderRow, {
    name: "OpenAI",
    model: "gpt-4o \xB7 \u5907\u7528\u7F51\u5173",
    on: providers.openai,
    onToggle: () => toggle("openai")
  }), /*#__PURE__*/React.createElement(ProviderRow, {
    name: "\u672C\u5730\u6A21\u578B",
    model: "qwen2.5 \xB7 Ollama :11434",
    on: providers.local,
    onToggle: () => toggle("local"),
    local: true
  })), /*#__PURE__*/React.createElement(Card, {
    variant: "inset",
    padding: 12,
    style: {
      marginBottom: 14,
      display: "flex",
      gap: 10,
      alignItems: "center"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 16
    }
  }, "\uD83D\uDD11"), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12.5,
      color: "var(--text-2)",
      lineHeight: "var(--lh-snug)"
    }
  }, "\u5BC6\u94A5\u4FDD\u5B58\u5728 ", /*#__PURE__*/React.createElement("b", {
    style: {
      color: "var(--chrome-1)"
    }
  }, "\u672C\u5730 SQLite"), "\uFF0C\u6C38\u4E0D\u4E0A\u4F20\u3002\u5BA1\u8BA1\u65E5\u5FD7\u5DF2\u5F00\u542F\u3002")), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "lg",
    block: true,
    icon: "\uFF0B"
  }, "\u6DFB\u52A0\u81EA\u5B9A\u4E49\u7F51\u5173")));
}
window.ProviderSheet = ProviderSheet;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/app/ProviderSheet.jsx", error: String((e && e.message) || e) }); }

// ui_kits/app/RecordsScreen.jsx
try { (() => {
// Black God App — Records / Memory screen. Long-term memory + cost dashboard.
const {
  Card,
  StatTile,
  CascadeBar,
  Badge,
  Chip,
  Avatar
} = window.BlackGodDesignSystem_7a1b36;
function MemoryRow({
  icon,
  title,
  sub,
  tone
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "12px 14px",
      background: "var(--bg-2)",
      border: "1px solid var(--line)",
      borderRadius: "var(--radius-sm)",
      boxShadow: "var(--panel-chrome)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 34,
      height: 34,
      flex: "0 0 auto",
      borderRadius: "var(--radius-xs)",
      background: "var(--surface-2)",
      border: "1px solid var(--line)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 16
    }
  }, icon), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 14.5,
      color: "var(--text)",
      fontWeight: 600
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12.5,
      color: "var(--text-3)",
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap"
    }
  }, sub)), tone && /*#__PURE__*/React.createElement(Badge, {
    tone: tone
  }, tone === "ok" ? "已学习" : "项目"));
}
function RecordsScreen() {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: "100%",
      overflowY: "auto",
      background: "var(--field-bg)",
      padding: "20px 16px calc(20px + var(--safe-bot))"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      letterSpacing: "var(--ls-label)",
      textTransform: "uppercase",
      color: "var(--text-3)",
      fontWeight: 600,
      marginBottom: 6
    }
  }, "RECORDS \xB7 \u8BB0\u5FC6"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--fs-h1)",
      fontWeight: 700,
      color: "var(--text)",
      marginBottom: 16,
      letterSpacing: "var(--ls-tight)"
    }
  }, "\u8D8A\u7528\u8D8A\u61C2\u4F60"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 10,
      marginBottom: 12
    }
  }, /*#__PURE__*/React.createElement(StatTile, {
    label: "\u672C\u6708\u7701\u4E0B",
    value: "\xA5248",
    delta: "\u2193 62% vs \u5168\u5927\u6A21\u578B",
    deltaTone: "ok",
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(StatTile, {
    label: "\u7F13\u5B58\u547D\u4E2D",
    value: "71",
    unit: "%",
    icon: "\u26A1",
    style: {
      flex: 1
    }
  })), /*#__PURE__*/React.createElement(Card, {
    variant: "raised",
    padding: 14,
    style: {
      marginBottom: 22
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12.5,
      color: "var(--text-2)",
      marginBottom: 10,
      fontWeight: 600
    }
  }, "\u4ECA\u5929 312 \u4E2A\u8BF7\u6C42\u7684\u7EA7\u8054\u5206\u5E03"), /*#__PURE__*/React.createElement(CascadeBar, {
    resolvedAt: 1
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      letterSpacing: "var(--ls-label)",
      textTransform: "uppercase",
      color: "var(--text-3)",
      fontWeight: 600,
      marginBottom: 10
    }
  }, "\u957F\u671F\u8BB0\u5FC6"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 8,
      marginBottom: 20
    }
  }, /*#__PURE__*/React.createElement(MemoryRow, {
    icon: "\uD83D\uDDA5",
    title: "\u670D\u52A1\u5668 \xB7 prod-sg",
    sub: "\u7981\u533A\uFF1A\u4E0D\u78B0\u6570\u636E\u5E93 \xB7 php-fpm \u8C03\u4F18\u8BB0\u5F55",
    tone: "project"
  }), /*#__PURE__*/React.createElement(MemoryRow, {
    icon: "\uD83D\uDCE6",
    title: "\u9879\u76EE \xB7 Black God PWA",
    sub: "\u6808\uFF1APython 3.11 \xB7 SQLite \xB7 CF Workers",
    tone: "project"
  }), /*#__PURE__*/React.createElement(MemoryRow, {
    icon: "\uD83E\uDDE0",
    title: "\u4E60\u60EF \xB7 \u4F60\u504F\u597D DeepSeek",
    sub: "\u4FBF\u5B9C\u4EFB\u52A1\u9ED8\u8BA4\u8D70 L3 \xB7 \u590D\u6742\u624D\u5347\u7EA7",
    tone: "ok"
  }), /*#__PURE__*/React.createElement(MemoryRow, {
    icon: "\uD83D\uDD11",
    title: "\u7981\u533A \xB7 \u5BC6\u94A5\u672C\u5730\u4FDD\u5B58",
    sub: "\u6C38\u4E0D\u4E0A\u4E91 \xB7 \u5BA1\u8BA1\u65E5\u5FD7\u5DF2\u5F00",
    tone: "ok"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      letterSpacing: "var(--ls-label)",
      textTransform: "uppercase",
      color: "var(--text-3)",
      fontWeight: 600,
      marginBottom: 10
    }
  }, "\u81EA\u52A8\u6C89\u6DC0\u7684\u6280\u80FD"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 8,
      flexWrap: "wrap"
    }
  }, /*#__PURE__*/React.createElement(Chip, {
    selected: true,
    icon: "\u26A1"
  }, "nginx-502-triage"), /*#__PURE__*/React.createElement(Chip, null, "ssh-safe-readonly"), /*#__PURE__*/React.createElement(Chip, null, "cost-router"), /*#__PURE__*/React.createElement(Chip, null, "pii-redact")));
}
window.RecordsScreen = RecordsScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/app/RecordsScreen.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.Chip = __ds_scope.Chip;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Pill = __ds_scope.Pill;

__ds_ns.Avatar = __ds_scope.Avatar;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.CascadeBar = __ds_scope.CascadeBar;

__ds_ns.StatTile = __ds_scope.StatTile;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Switch = __ds_scope.Switch;

})();
