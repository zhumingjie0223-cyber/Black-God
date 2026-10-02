# Black God · 抽拉卷帘与完成震动（2026-10-02）

权哥：要抽拉式 / 卷帘式动效；任务完成震动可开关；自己选型。

- [x] 1. 盘点：任务详情用 sheet；沙箱开关瞬时展开；AppState 有轻触但无完成震动开关。
- [x] 2. 选型落地：`BGPullDrawer` 卷帘抽拉 + `BGBottomDrawer` 底部抽屉。
- [x] 3. `taskCompleteHaptic` + 我的页双开关持久化；对话/演练/点亮挂钩。
- [x] 4. 单测/UI；构建 22；新 PR #138；等 CI。
- [ ] 5. CI 失败：卷帘高度裁掉 `execution.enabled`，改可靠展开后重推。

## 总结

选型为「抽拉卷帘」：沙箱开关横条装饰 + 弹簧卷开；任务详情从底部抽拉。震动在「我的 → 触感」可关。PR：https://github.com/zhumingjie0223-cyber/Black-God/pull/138
