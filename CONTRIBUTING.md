# 贡献指南

感谢你对 Black God 项目的关注！我们欢迎所有形式的贡献。

---

## 📋 目录

- [行为准则](#行为准则)
- [如何贡献](#如何贡献)
- [开发流程](#开发流程)
- [技能贡献](#技能贡献)
- [文档贡献](#文档贡献)
- [问题反馈](#问题反馈)

---

## 🤝 行为准则

参与本项目即表示你同意遵守以下准则：

- 尊重所有贡献者
- 使用友好、包容的语言
- 接受建设性的批评
- 关注对社区最有利的事情

---

## 🎯 如何贡献

### 1. Fork 仓库

点击右上角的 **Fork** 按钮，将仓库 fork 到你的账号下。

### 2. 克隆到本地

```bash
git clone https://github.com/你的用户名/blackgod.git
cd blackgod
```

### 3. 创建分支

```bash
git checkout -b feature/your-feature-name
```

分支命名规范：
- `feature/xxx` — 新功能
- `fix/xxx` — Bug 修复
- `docs/xxx` — 文档更新
- `refactor/xxx` — 代码重构

### 4. 进行修改

在你的分支上进行开发。

### 5. 提交更改

```bash
git add .
git commit -m "feat: 添加 xxx 功能"
```

提交信息规范（遵循 Conventional Commits）：
- `feat:` — 新功能
- `fix:` — Bug 修复
- `docs:` — 文档更新
- `style:` — 代码格式调整
- `refactor:` — 重构
- `test:` — 测试相关
- `chore:` — 构建/工具相关

### 6. 推送分支

```bash
git push origin feature/your-feature-name
```

### 7. 创建 Pull Request

在 GitHub 上创建 Pull Request，描述你的修改内容。

---

## 🔧 开发流程

### 前端开发

1. 修改 `web/index.html` 或相关文件
2. 在浏览器中测试（推荐 Chrome DevTools）
3. 确保移动端适配（使用浏览器移动设备模拟）
4. 提交前检查：
   - 代码格式是否规范
   - 是否有 console.log 遗留
   - 是否兼容主流浏览器

### iOS 开发

1. 打开 `ios-app/BlackGod.xcodeproj`
2. 使用 Xcode 进行开发
3. 在模拟器和真机上测试
4. 确保 UI 适配不同屏幕尺寸
5. 提交前运行测试

### 后端开发

后端代码不在本仓库，但欢迎提供接口设计建议。

---

## 🎨 技能贡献

Black God 的核心是技能系统。欢迎贡献新技能！

### 技能格式

创建 `docs/skills/your-skill-name.md`：

```markdown
# 技能名称

简短描述（1-2 句话）

## 触发关键词

当用户说以下关键词时触发：
- 关键词1
- 关键词2
- 关键词3

## 核心能力

1. 能力描述1
2. 能力描述2
3. 能力描述3

## 执行流程

1. 步骤1：xxx
2. 步骤2：xxx
3. 步骤3：xxx

## 工具依赖

- `shell_execute` — 执行命令
- `browser_use` — 浏览器自动化
- `file_write` — 写文件

## 示例

### 输入
用户: "帮我写一个冒泡排序"

### 输出
\`\`\`python
def bubble_sort(arr):
    n = len(arr)
    for i in range(n):
        for j in range(0, n-i-1):
            if arr[j] > arr[j+1]:
                arr[j], arr[j+1] = arr[j+1], arr[j]
    return arr
\`\`\`

## 注意事项

- 注意事项1
- 注意事项2
```

### 技能评审标准

- ✅ 有明确的使用场景
- ✅ 触发关键词清晰
- ✅ 执行流程完整
- ✅ 有实际使用示例
- ✅ 代码可运行（如果包含代码）

---

## 📖 文档贡献

### 文档类型

- **产品文档** — `docs/product/`
- **API 文档** — `docs/api/`
- **教程** — `docs/tutorials/`

### 文档规范

- 使用 Markdown 格式
- 添加目录（超过 3 个标题时）
- 代码块指定语言
- 添加示例和截图
- 中英文之间加空格

---

## 🐛 问题反馈

### 提交 Issue

发现 Bug 或有功能建议？[创建 Issue](https://github.com/uumingtian-max/blackgod/issues/new)

**Bug 报告模板：**

```markdown
## 问题描述
简短描述问题

## 复现步骤
1. 打开 xxx
2. 点击 xxx
3. 看到 xxx

## 预期行为
应该发生什么

## 实际行为
实际发生了什么

## 环境信息
- 浏览器：Chrome 120
- 操作系统：iOS 17.2
- 设备：iPhone 15 Pro
```

**功能建议模板：**

```markdown
## 功能描述
简短描述建议的功能

## 使用场景
为什么需要这个功能？

## 期望实现
希望如何实现

## 替代方案
有其他实现方式吗？
```

---

## 🎁 贡献者

感谢所有贡献者！

<!-- ALL-CONTRIBUTORS-LIST:START -->
<!-- 贡献者列表将自动生成 -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

---

## 📧 联系方式

- **Email**: blackgod@aquan.love
- **Telegram**: [@Boos8888](https://t.me/Boos8888)
- **GitHub Issues**: [提问讨论](https://github.com/uumingtian-max/blackgod/issues)

---

## 📜 许可证

本项目采用 [MIT License](LICENSE)。贡献的代码将遵循相同协议。

---

**再次感谢你的贡献！** 🎉
