// Black God App — Records / Memory screen. Long-term memory + cost dashboard.
const { Card, StatTile, CascadeBar, Badge, Chip, Avatar } = window.BlackGodDesignSystem_7a1b36;

function MemoryRow({ icon, title, sub, tone }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "12px 14px",
      background: "var(--bg-2)", border: "1px solid var(--line)", borderRadius: "var(--radius-sm)",
      boxShadow: "var(--panel-chrome)" }}>
      <div style={{ width: 34, height: 34, flex: "0 0 auto", borderRadius: "var(--radius-xs)",
        background: "var(--surface-2)", border: "1px solid var(--line)", display: "flex",
        alignItems: "center", justifyContent: "center", fontSize: 16 }}>{icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, color: "var(--text)", fontWeight: 600 }}>{title}</div>
        <div style={{ fontSize: 12.5, color: "var(--text-3)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{sub}</div>
      </div>
      {tone && <Badge tone={tone}>{tone === "ok" ? "已学习" : "项目"}</Badge>}
    </div>
  );
}

function RecordsScreen() {
  return (
    <div style={{ height: "100%", overflowY: "auto", background: "var(--field-bg)", padding: "20px 16px calc(20px + var(--safe-bot))" }}>
      <div style={{ fontSize: 12, letterSpacing: "var(--ls-label)", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 6 }}>RECORDS · 记忆</div>
      <div style={{ fontSize: "var(--fs-h1)", fontWeight: 700, color: "var(--text)", marginBottom: 16, letterSpacing: "var(--ls-tight)" }}>越用越懂你</div>

      {/* Cost dashboard */}
      <div style={{ display: "flex", gap: 10, marginBottom: 12 }}>
        <StatTile label="本月省下" value="¥248" delta="↓ 62% vs 全大模型" deltaTone="ok" style={{ flex: 1 }} />
        <StatTile label="缓存命中" value="71" unit="%" icon="⚡" style={{ flex: 1 }} />
      </div>
      <Card variant="raised" padding={14} style={{ marginBottom: 22 }}>
        <div style={{ fontSize: 12.5, color: "var(--text-2)", marginBottom: 10, fontWeight: 600 }}>今天 312 个请求的级联分布</div>
        <CascadeBar resolvedAt={1} />
      </Card>

      {/* Memory list */}
      <div style={{ fontSize: 12, letterSpacing: "var(--ls-label)", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>长期记忆</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8, marginBottom: 20 }}>
        <MemoryRow icon="🖥" title="服务器 · prod-sg" sub="禁区：不碰数据库 · php-fpm 调优记录" tone="project" />
        <MemoryRow icon="📦" title="项目 · Black God PWA" sub="栈：Python 3.11 · SQLite · CF Workers" tone="project" />
        <MemoryRow icon="🧠" title="习惯 · 你偏好 DeepSeek" sub="便宜任务默认走 L3 · 复杂才升级" tone="ok" />
        <MemoryRow icon="🔑" title="禁区 · 密钥本地保存" sub="永不上云 · 审计日志已开" tone="ok" />
      </div>

      <div style={{ fontSize: 12, letterSpacing: "var(--ls-label)", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>自动沉淀的技能</div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <Chip selected icon="⚡">nginx-502-triage</Chip>
        <Chip>ssh-safe-readonly</Chip>
        <Chip>cost-router</Chip>
        <Chip>pii-redact</Chip>
      </div>
    </div>
  );
}

window.RecordsScreen = RecordsScreen;
