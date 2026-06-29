Recessed obsidian field with a chrome focus ring. Pill shape for single-line, rounded-rect for multiline.

```jsx
<Input icon="🔍" placeholder="搜索记忆…" value={q} onChange={e=>setQ(e.target.value)} />
<Input multiline placeholder="发消息给 Black God…" trailing={<IconButton variant="chrome">↑</IconButton>} />
```
Pass `trailing` for an inline send/clear control. `multiline` grows as a textarea.
