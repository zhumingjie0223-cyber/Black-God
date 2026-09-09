# Black God 执行环境升级依据

日期：2026-09-09。研究对象：本机 OpenMinis，提交 4ef29002e88db1e20e462ec2ff46916e8a7dcb45。本文区分源码确认、已实现内容和未完成接入，不代表线上或真机验收。

## Minis 如何让模型实际做事

模型 API → AgentProvider 统一事件 → shell_execute / file_read / file_write → ISHExecutionCoordinator → ISHShellExecutor → iSH ARM64 Linux 用户态模拟 → Alpine rootfs → stdout、stderr、退出码 → tool_result → 下一轮模型。

- 模型本身通常仍由外部 API 提供，iSH 是执行程序的环境，不是提升模型参数规模的办法。
- `.gitmodules` 指向 OpenMinis/ish-arm64；BUILDING.md 指定构建 libish、libish_emu、libfakefs 和 Alpine aarch64 fakefs。不是直接使用 iOS 的 Process 执行 Linux 程序。
- 每次 shell 调用启动独立进程；终端会话状态不能作为跨调用的隐式依赖，脚本需明确目录和环境。
- Coordinator 按会话登记进程，并通过 fsContext 交给文件路由层。取消可以终止会话的进程组，避免后台子进程继续运行。
- 输出与退出码分开；失败输出也交给模型，让模型修正命令。超时路径终止进程后必须清理上下文和读管道线程。
- 内核有后台 CPU 调节接口。iOS 挂起和系统终止仍必须作为生命周期事件处理，不能承诺无限后台运行。
- NativeOffloads 把部分 Linux 工具调用桥接到 iOS 原生能力；ModelUseOffload 则能从脚本再次调用模型。这些桥接扩大能力，但每项都需要独立权限与预算管理。

源码入口（固定提交）：
- https://github.com/OpenMinis/OpenMinis/blob/4ef29002e88db1e20e462ec2ff46916e8a7dcb45/src/ios/Agent/Chat/AIChatViewModel+ToolDefinitions.swift
- https://github.com/OpenMinis/OpenMinis/blob/4ef29002e88db1e20e462ec2ff46916e8a7dcb45/src/ios/Agent/ISH/ISHExecutionCoordinator.swift
- https://github.com/OpenMinis/OpenMinis/blob/4ef29002e88db1e20e462ec2ff46916e8a7dcb45/src/ios/iSH/ISHShellExecutor.h
- https://github.com/OpenMinis/OpenMinis/blob/4ef29002e88db1e20e462ec2ff46916e8a7dcb45/src/ios/iSH/ISHKernel.h
- https://github.com/OpenMinis/OpenMinis/blob/4ef29002e88db1e20e462ec2ff46916e8a7dcb45/BUILDING.md

## 本轮已经落地的基础

Black God 实际聊天和 App Intents 的任务执行已接入 Anthropic Messages / OpenAI Chat Completions 原生工具调用。服务商调用 ID 保持原样，与内部 UUID 分离；工具声明仅包含已注册的 clock、calc、memory_search。

工具回合使用完整 JSON 响应，接收完成后才执行。保留服务商要求回传的 assistant 数据，仅用于当前回合，不展示、不写入对话存储。多工具结果逐一关联，未知工具和不符合 schema 的参数返回失败，重复参数复用已有结果。每步骤最多四回合，全部模型请求共享二十次预算；取消后不启动新工具。

规划与模型复核继续沿用原有流程。模型复核不等于外部事实核验。原生工具模式可在连接设置关闭，适配不支持工具的兼容接口；不会因一次服务商错误自动重发付费请求。新增真实工具测试入口，验证调用计算器及结果回传。

当前没有接入 shell/Linux，因此不向模型声明 shell。文件读写旧工具也没有开放到新模型路径，不能把占位工具数量当作实际能力。

## 下一阶段实施顺序与验收条件

1. **运行内核的隔离实验**：固定 iSH 源码版本和 rootfs 校验值，分别构建真机与模拟器目标。验证首次安装、重复启动、安装失败恢复；在 iPhone 上执行 uname、printf、失败命令及简单 Python 脚本，记录真实退出码和耗时。发布前处理依赖许可证与相应源码分发；Black God 当前 LICENSE 为 MIT，Minis BUILDING.md 明确其链接的 iSH 为 GPLv3，不能直接复制后继续把整个发行包当作只有 MIT 依赖。
2. **受控工作目录**：会话独立目录；先开放列目录、读文本、创建任务产物，再接命令执行。拒绝越界路径与符号链接逃逸；应用凭据、内部数据库不挂载到 Linux。并发任务不能互相覆盖文件。
3. **进程生命周期**：命令、cwd、timeout、stdout、stderr、exitCode、PID 和执行状态使用结构化记录。取消/超时/正常退出竞争只能结束一次；清理整个进程组与读管道。输出设字节上限，不能用“输出不为空”判成功。
4. **任务证据与恢复**：保存工具输入摘要、退出码、产物路径和结果校验。进程中断后显示未完成；恢复前核对执行是否已发生，避免重复写入。模型总结必须依据这些证据。
5. **能力桥接**：先做文件与脚本，再按真实需求接网络、浏览器和系统原生接口。权限由宿主验证，不交给模型自我判断。模型嵌套调用共享父任务预算，防止脚本递归调用绕过上限。
6. **验收矩阵**：每个启用服务商实测聊天、工具、错误鉴权、限流、断网、取消；真机测后台/前台切换、锁屏、低内存终止、重复启动、长输出和并发取消。记录耗时分位数、失败率、内存峰值及无遗留进程证据。

## 当前发布门槛

自动化测试与构建通过只能证明所覆盖的代码路径。真实 API 凭据、模型权限、真机持续运行、Linux 内核整合及分发方案尚未完成。因此当前状态应表述为“原生工具基础已实现，生产验收仍在推进”，不能宣称已完成工业级验收。

## 2026-09-09 后续实施更新

上述“当前没有接入 shell”描述的是第一阶段状态。现已固定 iSH 3f6384c70eefd1a370f121d3492a5f21f7767df9 并构建真机/模拟器库，导入校验后的干净 Alpine 3.22.1 ARM64。实际启动、脚本、退出码、多次执行、取消/超时/超量输出、子进程清理已通过模拟器测试。工具页提供命令入口和默认关闭的 AI 执行开关，模型可调用 shell_execute。

本轮 182 项测试通过（iOS65，JS84，Python33）。模型闭环测试使用模拟模型响应，但计算与 shell 实际执行。Release 为无签名 iPhoneOS 构建，未在物理 iPhone 上运行。上游头文件仍有 clock_t 窄化编译警告，不能声称整个原生依赖零警告。

仍待完成：强会话隔离、真实模型 API 联调、物理设备的资源/长任务测试、完整第三方源码分发与发行审核。当前共享 rootfs 是明确标记的实验执行环境，不是已经通过工业级生产验收。
