# Black God · 神枢 Nexus

懂你生活工作的智能助理。当前发布入口为原生 iPhone 应用，采用 SwiftUI，最低支持 iOS 17，面向 Apple App Store 发布。

![Black God](web/logo.png)

## 当前架构

- **Black God** 是产品品牌，**神枢 Nexus** 是原生客户端和任务运行时，助手身份为 Black God AI。
- **原生 iOS 客户端**位于 `ios-app/`：对话、工作台、任务记录、配置、工具调度与本地存储都在此目录维护。
- **模型连接**由用户配置服务商密钥，客户端直接向所配置的模型服务商发送请求。密钥保存在 iOS Keychain；发送请求时会用于向对应服务商鉴权。
- **本地数据**包括用户主动收藏的记忆、最近 50 次任务历史和中断检查点。当前对话用于本次会话上下文；使用模型时，相关对话与检索出的记忆会发送给所选服务商，首次使用各服务商前需明确确认共享范围。具体处理见应用内隐私政策。
- **枢语 Shuyu**是独立的 JS/Python 语言引擎，保留在 `shuyu/`。当前 iOS 工程没有导入它，构建或使用 iOS 应用无需部署枢语 Worker。

早期 Cloudflare Workers / Durable Object 服务和网页工作台属于历史架构。当前分支已没有 `web/nexus-do/`，旧文档中的该路径、部署命令和测试数量不能作为当前发布步骤。

## 当前任务能力

输入目标后，客户端请求模型制定步骤，逐步执行，并显示计划变化、工具输入与返回结果。运行时通过 `onUpdate` 更新界面和检查点；任务可停止，恢复时跳过已完成步骤，继续未完成部分。流程完成、失败或取消均保存到本机历史，保留最近 50 次，支持查看、删除和分享结果。

默认工具是本机时钟、受限四则计算和原样文本回传。工作台也可直接使用时钟和计算器。当前没有联网网页检索、手机系统控制或 shell 命令执行；仓库内的文件与 shell 工具类型不代表已向任务开放这些能力。

结果检查只判断非空、长度、代码块结构以及工具调用是否处理完毕，不验证事实正确性，也不保证用户目标已经满足。模型内容和重要结论仍需核对。

记忆由用户点击收藏或在管理页主动添加；不会把全部对话自动保存为长期记忆。最多 200 条，每条 4000 字；检索支持中文和英文，最多返回 8 条、合计不超过 6000 字。记忆、历史和检查点使用原子写入，iOS 文件受系统数据保护；读写失败会显示错误。清除全部数据会尝试删除本机文件与钥匙串条目，并报告未完成的删除。

## 本地测试

在 Mac 上执行真实 Swift 源码回归，测试使用隔离网络边界和临时存储，不需要 API Key 或签名：

```bash
make test-ios
make test-shuyu
# 两组一起执行
make test
```

`tests/run_ios_runtime_tests.sh` 覆盖计划、工具执行、停止与恢复、模型响应桥接；`ios-app/StorageTests/run.sh` 覆盖存储上限、双语检索、重载、损坏文件和清除失败。通过这些测试仍需继续验证原生界面、真机网络、正式归档和 App Store 提交。

## 本地构建

在已配置 iOS SDK 的 Mac 上，使用 Xcode 和 XcodeGen：

```bash
cd ios-app
xcodegen generate
xcodebuild build \
  -project BlackGod888.xcodeproj \
  -scheme BlackGod888 \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=''
```

此命令验证源码与资源能否完成构建。正式分发需要 Apple 开发者团队、签名证书、描述文件，以及 App Store Connect 中对应的应用记录。版本号、构建号和 Bundle ID 以 `ios-app/project.yml` 为准。

上架步骤、商店文案和隐私材料见 [App Store 提交指南](ios-app/AppStore/SUBMIT_GUIDE.md)。上传与提交审核的凭据应通过本机安全存储或发布平台的机密配置注入，不写进仓库。

## 枢语版本与测试

本仓 `shuyu/` 保留了较新的 **v4.1 引擎**（JS 包版本 1.2.0、Python 包版本 4.1.0），包含汉译反查、语义检索、按义造词和两种实现的对应测试。

[独立 shuyu-lang 仓库](https://github.com/zhumingjie0223-cyber/shuyu-lang)当前仍有较旧基线。统一发布前以本仓已验证的 v4.1 能力为迁移起点，逐项合入独立仓的修复并运行回归；不要用旧版覆盖本仓，也不要仅凭容量相同或旧同步脚本通过便认定全部接口相同。

```bash
cd shuyu
npm test
python3 -m unittest discover -s tests -v
```

## 目录导航

| 路径 | 当前用途 |
|---|---|
| `ios-app/` | 原生 iOS 应用源码与工程定义 |
| `ios-app/AppStore/` | 隐私政策、商店文案、截图与提交说明 |
| `shuyu/` | 枢语 v4.1 引擎、词表与测试 |
| `web/` | 历史网页资产与现用品牌图标，不是 iOS 运行入口 |
| `assets/`、`ui-spec/` | 品牌资产和设计参考 |
| `android/` | 历史 Android 材料，独立于本次 iOS 发布 |
| `docs/` | 项目文档与历史记录 |
| `docs/archive/` | 历史服务、页面、配置与旧工程归档 |

更详细的源码入口见 [STRUCTURE.md](STRUCTURE.md)。历史规划与架构资料见 [文档导航](docs/README.md)，执行前应与当前工程核对。

## 版权

© 阿权 / 路飞。授权条款见 [LICENSE](LICENSE)。
