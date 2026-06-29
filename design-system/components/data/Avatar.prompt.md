Identity mark — the metallic 神 logo for the assistant, a chrome initial plate for the user.

```jsx
<Avatar kind="god" src="assets/logo-god.png" size={40} />
<Avatar kind="user" label="林" />
```
For the assistant always pass `kind="god"` + the logo asset. User avatars fall back to the first character of `label`.
