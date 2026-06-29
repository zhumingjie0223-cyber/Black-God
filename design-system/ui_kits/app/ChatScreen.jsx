// Black God App — Chat screen. The execution hub: messages, a tool/cascade
// trace, the consent prompt, and the chrome composer. Reuses DS primitives.
const { Avatar, Badge, CascadeBar, Card, IconButton, Input, Button } = window.BlackGodDesignSystem_7a1b36;

function ToolTrace({ steps }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6, margin: "4px 0 2px" }}>
      {steps.map((s, i) => (
        <div key={i} style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13, color: "var(--text-2)" }}>
          <span style={{ width: 16, textAlign: "center", color: s.tone === "ok" ? "var(--ok)" : s.tone === "run" ? "var(--run)" : "var(--chrome-3)" }}>
            {s.tone === "ok" ? "✓" : s.tone === "run" ? "◐" : "·"}
          </span>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 12.5, color: "var(--chrome-2)" }}>{s.tool}</span>
          <span style={{ color: "var(--text-3)" }}>{s.note}</span>
        </div>
      ))}
    </div>
  );
}

function GodMessage({ children }) {
  return (
    <div style={{ display: "flex", gap: 10, alignItems: "flex-start" }}>
      <Avatar kind="god" src="../../assets/logo-god.png" size={34} />
      <div style={{ flex: 1, minWidth: 0 }}>{children}</div>
    </div>
  );
}

function UserMessage({ children }) {
  return (
    <div style={{ display: "flex", justifyContent: "flex-end" }}>
      <div style={{
        maxWidth: "78%", padding: "10px 14px", borderRadius: "16px 16px 4px 16px",
        background: "var(--bubble-user)", color: "var(--bubble-user-ink)",
        fontSize: "var(--fs-body)", fontWeight: 500, lineHeight: "var(--lh-snug)",
        boxShadow: "var(--inset-hi-2)",
      }}>{children}</div>
    </div>
  );
}

function ChatScreen({ onOpenProvider }) {
  const [text, setText] = React.useState("");
  const [consented, setConsented] = React.useState(false);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: "var(--field-bg)" }}>
      {/* Top bar */}
      <div style={{
        display: "flex", alignItems: "center", gap: 10, padding: "14px 16px",
        background: "rgba(10,11,14,.7)", backdropFilter: "var(--blur-bar)",
        borderBottom: "1px solid var(--line)", flex: "0 0 auto",
      }}>
        <img src="../../assets/logo-god.png" style={{ width: 28, height: 28, filter: "drop-shadow(0 2px 8px var(--chrome-glow))" }} />
        <div style={{ display: "flex", flexDirection: "column", lineHeight: 1.2 }}>
          <span style={{ fontSize: 15, fontWeight: 700, letterSpacing: ".08em",
            background: "var(--chrome-grad)", WebkitBackgroundClip: "text", backgroundClip: "text", WebkitTextFillColor: "transparent" }}>BLACK GOD</span>
          <span style={{ fontSize: 11, color: "var(--text-3)" }}>本地优先 · 私人执行中枢</span>
        </div>
        <div style={{ flex: 1 }} />
        <button onClick={onOpenProvider} style={{
          display: "inline-flex", alignItems: "center", gap: 6, height: 30, padding: "0 11px",
          borderRadius: "var(--radius-pill)", background: "var(--surface)", border: "1px solid var(--line-chrome)",
          color: "var(--chrome-1)", fontSize: 12.5, fontWeight: 500, cursor: "pointer", fontFamily: "var(--font-sans)",
        }}>
          <span style={{ width: 7, height: 7, borderRadius: "50%", background: "var(--ok)", boxShadow: "0 0 6px var(--ok)" }} />
          DeepSeek
        </button>
      </div>

      {/* Messages */}
      <div style={{ flex: 1, overflowY: "auto", padding: "18px 16px", display: "flex", flexDirection: "column", gap: 16 }}>
        <UserMessage>帮我把生产服务器的 nginx 日志拉下来，看看昨晚 502 是怎么回事</UserMessage>

        <GodMessage>
          <div style={{ fontSize: "var(--fs-body)", color: "var(--text)", lineHeight: "var(--lh-body)", marginBottom: 8 }}>
            记得你的 <b style={{ color: "var(--chrome-1)" }}>prod-sg</b> 服务器（你设过禁区：不碰数据库）。我先只读日志：
          </div>
          <Card variant="inset" padding={12} style={{ marginBottom: 8 }}>
            <ToolTrace steps={[
              { tool: "ssh.run", note: "tail -n 2000 /var/log/nginx/error.log", tone: "ok" },
              { tool: "grep", note: "502 · 命中 47 行 · 22:14–22:31", tone: "ok" },
              { tool: "analyze", note: "upstream timeout · php-fpm 队列打满", tone: "ok" },
            ]} />
          </Card>
          <div style={{ fontSize: "var(--fs-body)", color: "var(--text)", lineHeight: "var(--lh-body)" }}>
            根因：<b style={{ color: "var(--chrome-1)" }}>php-fpm</b> 在 22:14 队列打满，upstream 超时。建议把 <code style={{ fontFamily: "var(--font-mono)", color: "var(--warn)" }}>pm.max_children</code> 从 16 调到 32。
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 10 }}>
            <Badge tone="ok" dot>L2 本地工具</Badge>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--text-3)" }}>¥0.0008 · 1.4s · 未上云</span>
          </div>
        </GodMessage>

        {/* Consent prompt */}
        {!consented ? (
          <GodMessage>
            <Card variant="chrome" padding={14}>
              <div style={{ fontSize: 13.5, color: "var(--chrome-1)", fontWeight: 600, marginBottom: 4 }}>需要你批准一次写操作</div>
              <div style={{ fontSize: 13.5, color: "var(--text-2)", lineHeight: "var(--lh-snug)", marginBottom: 12 }}>
                改 <code style={{ fontFamily: "var(--font-mono)", color: "var(--chrome-1)" }}>php-fpm.conf</code> 并 reload — 会写入服务器。我不会动数据库。
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <Button variant="primary" size="sm" onClick={() => setConsented(true)}>允许执行</Button>
                <Button variant="ghost" size="sm">仅预览 diff</Button>
              </div>
            </Card>
          </GodMessage>
        ) : (
          <GodMessage>
            <Card variant="inset" padding={12}>
              <ToolTrace steps={[
                { tool: "edit", note: "pm.max_children 16 → 32", tone: "ok" },
                { tool: "ssh.run", note: "systemctl reload php-fpm", tone: "ok" },
                { tool: "verify", note: "502 归零 · 压测 200rps 通过", tone: "ok" },
                { tool: "memory.write", note: "记住 prod-sg 调优记录", tone: "ok" },
              ]} />
            </Card>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 10 }}>
              <Badge tone="ok" dot>闭环完成</Badge>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--text-3)" }}>已沉淀技能 · nginx-502-triage</span>
            </div>
          </GodMessage>
        )}
      </div>

      {/* Composer */}
      <div style={{ padding: "10px 14px calc(10px + var(--safe-bot))", borderTop: "1px solid var(--line)",
        background: "rgba(10,11,14,.7)", backdropFilter: "var(--blur-bar)", flex: "0 0 auto" }}>
        <Input multiline placeholder="发消息给 Black God…" value={text} onChange={(e) => setText(e.target.value)}
          icon="＋"
          trailing={<IconButton variant="chrome" size="md">↑</IconButton>} />
      </div>
    </div>
  );
}

window.ChatScreen = ChatScreen;
