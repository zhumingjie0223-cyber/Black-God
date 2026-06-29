The signature Black God visualization — the L0–L6 cost cascade (缓存→规则→本地工具→便宜模型→贵模型→深度推理→人工). The resolving level lights up in chrome; cheaper levels read as "saved".

```jsx
<CascadeBar resolvedAt={0} />        {/* cache hit — maximum saving */}
<CascadeBar resolvedAt={3} />        {/* fell through to a cheap model */}
<CascadeBar compact resolvedAt={2} /> {/* thin inline indicator */}
```
Use it in dashboards and message footers to show how a request was answered. `compact` gives a thin 8px bar for inline use.
