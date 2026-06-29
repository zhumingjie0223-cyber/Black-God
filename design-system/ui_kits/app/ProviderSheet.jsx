// Black God App — Provider Hub bottom sheet. Bring-your-own model gateway.
const { Card, Switch, Badge, Button, IconButton } = window.BlackGodDesignSystem_7a1b36;

function ProviderRow({ name, model, status, on, onToggle, local }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "13px 14px",
      background: "var(--bg-2)", border: `1px solid ${on ? "var(--line-chrome)" : "var(--line)"}`,
      borderRadius: "var(--radius-sm)", boxShadow: on ? "var(--panel-chrome), var(--glow-chrome-sm)" : "none",
      transition: "all var(--t-base) var(--ease-out)" }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ fontSize: 15, color: "var(--text)", fontWeight: 600 }}>{name}</span>
          {local && <Badge tone="ok">本地</Badge>}
        </div>
        <div style={{ fontSize: 12.5, color: "var(--text-3)", fontFamily: "var(--font-mono)", marginTop: 2 }}>{model}</div>
      </div>
      <Switch checked={on} onChange={onToggle} />
    </div>
  );
}

function ProviderSheet({ open, onClose }) {
  const [providers, setProviders] = React.useState({ deepseek: true, anthropic: true, openai: false, local: true });
  const toggle = (k) => setProviders((p) => ({ ...p, [k]: !p[k] }));

  return (
    <div style={{
      position: "absolute", inset: 0, zIndex: 20, pointerEvents: open ? "auto" : "none",
    }}>
      {/* Scrim */}
      <div onClick={onClose} style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,.55)",
        opacity: open ? 1 : 0, transition: "opacity var(--t-base)", backdropFilter: open ? "var(--blur-soft)" : "none" }} />
      {/* Sheet */}
      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0,
        transform: open ? "translateY(0)" : "translateY(100%)",
        transition: "transform var(--t-slow) var(--ease-sheet)",
        background: "var(--bg-1)", borderTop: "1px solid var(--line-chrome)",
        borderRadius: "22px 22px 0 0", padding: "10px 16px calc(20px + var(--safe-bot))",
        boxShadow: "var(--shadow-xl)",
      }}>
        <div style={{ width: 40, height: 4, borderRadius: 99, background: "var(--line-2)", margin: "0 auto 14px" }} />
        <div style={{ display: "flex", alignItems: "center", marginBottom: 4 }}>
          <div>
            <div style={{ fontSize: "var(--fs-h2)", fontWeight: 700, color: "var(--text)" }}>Provider Hub</div>
            <div style={{ fontSize: 13, color: "var(--text-3)" }}>自己接入模型 · 不被单一厂商绑架</div>
          </div>
          <div style={{ flex: 1 }} />
          <IconButton variant="soft" onClick={onClose}>✕</IconButton>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 9, margin: "16px 0 14px" }}>
          <ProviderRow name="DeepSeek" model="deepseek-chat · L3 默认" on={providers.deepseek} onToggle={() => toggle("deepseek")} />
          <ProviderRow name="Anthropic" model="claude · L4 升级路径" on={providers.anthropic} onToggle={() => toggle("anthropic")} />
          <ProviderRow name="OpenAI" model="gpt-4o · 备用网关" on={providers.openai} onToggle={() => toggle("openai")} />
          <ProviderRow name="本地模型" model="qwen2.5 · Ollama :11434" on={providers.local} onToggle={() => toggle("local")} local />
        </div>

        <Card variant="inset" padding={12} style={{ marginBottom: 14, display: "flex", gap: 10, alignItems: "center" }}>
          <span style={{ fontSize: 16 }}>🔑</span>
          <span style={{ fontSize: 12.5, color: "var(--text-2)", lineHeight: "var(--lh-snug)" }}>
            密钥保存在 <b style={{ color: "var(--chrome-1)" }}>本地 SQLite</b>，永不上传。审计日志已开启。
          </span>
        </Card>

        <Button variant="primary" size="lg" block icon="＋">添加自定义网关</Button>
      </div>
    </div>
  );
}

window.ProviderSheet = ProviderSheet;
