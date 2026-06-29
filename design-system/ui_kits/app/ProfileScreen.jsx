// Black God App — Profile / settings. Identity, privacy guardrails, the
// brand mark. Where "data stays in your hands" is made concrete.
const { Avatar, Card, Switch, Badge, Button, IconButton } = window.BlackGodDesignSystem_7a1b36;

function SettingRow({ icon, title, sub, control }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "13px 14px",
      background: "var(--bg-2)", border: "1px solid var(--line)", borderRadius: "var(--radius-sm)" }}>
      <div style={{ width: 32, height: 32, flex: "0 0 auto", borderRadius: "var(--radius-xs)",
        background: "var(--surface-2)", border: "1px solid var(--line)", display: "flex",
        alignItems: "center", justifyContent: "center", fontSize: 15 }}>{icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, color: "var(--text)", fontWeight: 600 }}>{title}</div>
        {sub && <div style={{ fontSize: 12, color: "var(--text-3)" }}>{sub}</div>}
      </div>
      {control}
    </div>
  );
}

function ProfileScreen({ onOpenProvider }) {
  const [localFirst, setLocalFirst] = React.useState(true);
  const [pii, setPii] = React.useState(true);
  const [audit, setAudit] = React.useState(true);
  const [cloud, setCloud] = React.useState(false);

  return (
    <div style={{ height: "100%", overflowY: "auto", background: "var(--field-bg)", padding: "26px 16px calc(20px + var(--safe-bot))" }}>
      {/* Identity */}
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10, marginBottom: 22 }}>
        <img src="../../assets/logo-god.png" style={{ width: 76, height: 76, filter: "drop-shadow(0 6px 24px var(--chrome-glow))" }} />
        <div style={{ fontSize: 20, fontWeight: 700, color: "var(--text)" }}>林 · 你的私人执行中枢</div>
        <Badge tone="chrome">本地优先 · 数据在你手里</Badge>
      </div>

      <div style={{ fontSize: 12, letterSpacing: "var(--ls-label)", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>隐私护栏</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8, marginBottom: 20 }}>
        <SettingRow icon="🔒" title="本地优先存储" sub="密码 · 配置 · 记忆默认本地" control={<Switch checked={localFirst} onChange={setLocalFirst} />} />
        <SettingRow icon="🛡" title="PII 检测" sub="发送前自动识别并脱敏" control={<Switch checked={pii} onChange={setPii} />} />
        <SettingRow icon="📋" title="审计日志" sub="每次工具调用可回溯" control={<Switch checked={audit} onChange={setAudit} />} />
        <SettingRow icon="☁️" title="同步到云端" sub="默认关闭 · 你来决定" control={<Switch checked={cloud} onChange={setCloud} />} />
      </div>

      <div style={{ fontSize: 12, letterSpacing: "var(--ls-label)", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>接入</div>
      <Card variant="raised" padding={14} style={{ marginBottom: 12, display: "flex", alignItems: "center", gap: 12 }}>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 14.5, color: "var(--text)", fontWeight: 600 }}>Provider Hub</div>
          <div style={{ fontSize: 12.5, color: "var(--text-3)" }}>4 个已接入 · DeepSeek 默认</div>
        </div>
        <Button variant="secondary" size="sm" onClick={onOpenProvider} icon="🔌">管理</Button>
      </Card>

      <Button variant="danger" size="md" block icon="🗑" style={{ marginTop: 8 }}>清除全部本地记忆</Button>
    </div>
  );
}

window.ProfileScreen = ProfileScreen;
