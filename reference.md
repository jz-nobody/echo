# Agent Island - 参考资料

> 最后更新：2026-05-20  
> 用途：开发过程中的竞品参考、技术参考和视觉参考

---

## 1. 主要竞品

### 1.1 VibeIsland (Vibe Island)

| 属性 | 详情 |
|------|------|
| 官网 | https://vibeisland.app/ |
| 定位 | Mac 刘海区 AI Agent 灵动岛 |
| 技术栈 | Pure Swift，native macOS overlay |
| 支持 Agent 数 | 16+ |
| 支持终端 | iTerm2, Ghostty, Terminal.app |
| 支持 Agent | Claude Code, Codex, OpenCode, Gemini CLI, Factory Droid 等 |
| 接入方式 | "Zero config" local CLI hooks + "Claude Code compatible hooks" |
| 定价 | 付费（通行证模式） |
| 数据安全 | 所有数据本地处理，不上传云端 |

**核心功能特征：**
- 嵌入刘海区的实时状态监控
- hover 展开详细面板
- 权限审批（diff 预览 + Allow/Deny）
- 选择题交互（多选项 + 快捷键）
- 点击跳转到 Agent 所在终端会话
- 智能抑制（前台终端时不弹出）
- 通知过滤（后台会话过滤）
- 声音提醒（按事件类型配置）
- 快捷键确认（Cmd+Y/N/1/2/3）
- 子代理活动详情展示
- 空闲会话自动清理

**开发者信息：**
- 即刻平台分享："最近每天烧几亿Tokens，做了一款很有趣的Mac「灵动岛」App"
- 来源：https://m.okjike.com/originalPosts/69cbdd7625bae56612855591

---

### 1.2 Claude Island (Reddit 项目)

| 属性 | 详情 |
|------|------|
| 来源 | https://www.reddit.com/r/ClaudeCode/comments/1pibst6/claude_island_dynamic_island_for_claude_code/ |
| 定位 | 专为 Claude Code 的 Dynamic Island |
| 说明 | 早期项目，功能可能不如 VibeIsland 完善 |

---

## 2. 开源参考项目

### 2.1 open-vibe-island (Open Island)

| 属性 | 详情 |
|------|------|
| GitHub | https://github.com/Octane0411/open-vibe-island |
| 中文 README | https://github.com/Octane0411/open-vibe-island/blob/main/README.zh-CN.md |
| 定位 | VibeIsland 的开源替代 |
| 技术栈 | SwiftUI + AppKit |
| 支持 Agent | Claude Code (cc), Codex, OpenCode |
| 终端集成 | Ghostty, iTerm2 |
| 核心能力 | 实时控制 + 会话状态 + 权限审批 |
| 数据安全 | 本地优先 (local-first) |

**技术参考价值：**
- 可参考其 SwiftUI + AppKit 的混合架构实现
- 可参考其终端 hook 的具体实现方式（文件监听 vs PTY）
- 可参考其 Accessibility API 的使用方式
- 代码开源，可直接学习窗口定位和动画实现

**注意：** 截至 2026-05-20，GitHub 直接访问超时，可能需要通过镜像站或 VPN 访问源码。镜像参考：https://gitcode.com/gh_mirrors/op/open-vibe-island

---

## 3. 技术参考

### 3.1 macOS Notch 检测
- `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`（macOS 12+）
- 通过屏幕 safeAreaInsets 推算刘海物理尺寸
- 各机型刘海尺寸数据需实际测量或从社区获取

### 3.2 QoderWork MCP Adaptor
- 协议：JSON-RPC 2.0 over HTTP
- 端口：127.0.0.1:52345
- Unix Socket：/tmp/qoderwork-mcp.sock
- 核心工具：qoder_list_tasks, qoder_get_task_detail, qoder_respond_task, qoder_send_message, qoder_cancel_task, qoder_start_task
- serverInfo: name="qoder-work-mcp-adaptor", version="1.0.0"
- capabilities: {tools: {}, resources: {}}
- 注意：resources/list 返回 -32601 "Method not found"（未实现），只能用 tools

### 3.3 Claude Code 潜在日志路径
- `~/.claude/` — Claude Code 配置和会话目录（需实际验证）
- 可能的格式：JSONL（每行一个事件对象）
- 事件类型推测：thinking, tool_use, permission_request, ask, result

### 3.4 相关技术文章/讨论
- VibeIsland + OpenClaw + Claude Code 使用演示：https://www.youtube.com/watch?v=k3F36e2rjnA
- Best Vibe Coding Tools 2026: https://nimbalyst.com/blog/best-vibe-coding-tools-2026/
- Vibe Coding Agent Swarm (Adrian Cockcroft): https://adrianco.medium.com/vibe-coding-is-so-last-month-my-first-agent-swarm-experience-with-claude-flow-414b0bd6f2f2

---

## 4. 竞品参考截图

以下截图来自 VibeIsland，存储在本地。开发时应作为 1:1 复刻的视觉参考。

### 4.1 核心 UI 状态

| 编号 | 文件路径 | 内容描述 |
|------|---------|---------|
| IMG-001 | `/Users/wm338658/Downloads/运行中.jpg` | **缩小态 - 运行中**：刘海区紧凑 bar，蓝色动画像素图标 + "运行中" 文案 + 用户名 + 会话数 |
| IMG-002 | `/Users/wm338658/Downloads/已完成.jpg` | **缩小态 - 已完成**：刘海区紧凑 bar，绿色静止图标 + "已完成" 文案 |
| IMG-003 | `/Users/wm338658/Downloads/运行中hover.jpg` | **扩展态 - 运行中详情**：hover 展开面板，显示用户输入摘要 + 当前工具调用（Bash claude --help）+ "自动批准 ✕" 开关 |
| IMG-004 | `/Users/wm338658/Downloads/多agent列表.JPG` | **扩展态 - 多任务列表**：多个 Agent 同时运行，每行显示任务名 + Agent 标签(Claude/Codex) + 终端标签(iTerm/Ghostty) + 运行时长。包含子代理详情 |
| IMG-005 | `/Users/wm338658/Downloads/点击任务唤起agent.jpg` | **扩展态 - 完成+跳转**：任务完成后显示 "Done — click to jump" 绿色链接 + 工具执行日志（Write/Bash 结果 "3 passed"）+ 其他活跃会话列表 |

### 4.2 确认交互

| 编号 | 文件路径 | 内容描述 |
|------|---------|---------|
| IMG-006 | `/Users/wm338658/Downloads/用户确认项.jpg` | **权限审批面板**：⚠ Edit src/auth/middleware.ts + diff 预览（红/绿行）+ "+3 -1" 变更统计 + Deny(⌘N) / Allow(⌘Y) 按钮 |
| IMG-007 | `/Users/wm338658/Downloads/用户确认项2.jpg` | **选择题面板**：💬 Claude asks + 问题文案 + 多个选项卡片 + ⌘1/⌘2/⌘3 快捷键 |

### 4.3 设置面板

| 编号 | 文件路径 | 内容描述 |
|------|---------|---------|
| IMG-008 | `/Users/wm338658/Downloads/通用设置.jpg` | **通用设置（上）**：登录时打开、悬停延迟(0.15s)、智能抑制（Agent终端在前台时不展开）、全屏时隐藏、鼠标离开自动收起、自动提醒停留时长(5s) |
| IMG-009 | `/Users/wm338658/Downloads/通用设置2.jpg` | **通用设置（下）**：空闲会话自动清理(2h for Codex/OpenCode/Cursor)、Agent Team 队友完成时自动展开(OFF)、禁用点击跳转 |
| IMG-010 | `/Users/wm338658/Downloads/显示设置.jpg` | **显示设置（上）**：两种刘海模式（简洁=图标/详细=标题+状态）、显示器选择、面板字体大小(11pt)、完成卡片高度(90pt)、最大面板高度(560pt)、最大面板宽度(640pt) |
| IMG-011 | `/Users/wm338658/Downloads/显示设置2.jpg` | **显示设置（下）**：刘海宽度微调(0pt=自动)、刘海高度微调(0pt=自动)、显示代理活动详情开关 |
| IMG-012 | `/Users/wm338658/Downloads/声音设置.jpg` | **声音设置**：每个事件独立配置音效 — 会话开始/任务完成/任务错误/需要审批/任务确认/上下文限制/闲置提醒/连续提交检测。音量滑块(30%)。各事件可选不同音色集 |
| IMG-013 | `/Users/wm338658/Downloads/通知过滤.jpg` | **通知过滤**：内置过滤规则(Codex Memory Consolidation/Memory Writer/Guardian-AutoReview/Chronicle Summary/Claude-Mem)。自定义过滤：按目录路径片段 + 按首条提示词前缀。右键会话卡片快捷添加 |

---

## 5. 截图关键设计细节提取

### 从截图中可量化的设计参数

| 参数 | 值 | 来源 |
|------|-----|------|
| 悬停延迟 | 0.15s | IMG-008 |
| 自动提醒停留时长 | 5s | IMG-008 |
| 空闲清理时间 | 2h（Codex/OpenCode/Cursor） | IMG-009 |
| 面板字体大小 | 11pt | IMG-010 |
| 完成卡片高度 | 90pt | IMG-010 |
| 最大面板高度 | 560pt | IMG-010 |
| 最大面板宽度 | 640pt | IMG-010 |
| 刘海宽度默认 | 0pt（macOS API 自动检测） | IMG-011 |
| 刘海高度默认 | 0pt（macOS API 自动检测） | IMG-011 |
| 默认音量 | 30% | IMG-012 |

### 交互模式

| 模式 | 描述 | 来源 |
|------|------|------|
| 智能抑制 | Agent 终端标签页在前台时不自动展开面板 | IMG-008 |
| 全屏隐藏 | 全屏模式下隐藏缩小态 | IMG-008 |
| Agent Team 处理 | 子代理完成时默认不展开（可配置） | IMG-009 |
| 点击跳转可禁用 | 设置中可关闭 | IMG-009 |
| 简洁/详细模式 | 缩小态两种信息密度 | IMG-010 |
| 子代理详情 | 可切换是否显示子代理的工具调用细节 | IMG-011 |
| 右键快捷操作 | 右键会话卡片可添加到过滤规则 | IMG-013 |

---

## 6. 有用的开发者社区链接

- VibeIsland 开发者即刻动态：https://m.okjike.com/originalPosts/69cbdd7625bae56612855591
- Reddit ClaudeCode 社区讨论：https://www.reddit.com/r/ClaudeCode/comments/1sjewmg/i_burned_out_my_max_plan_for_this_a_dynamic/
- GitHub Topics (open-island)：https://github.com/topics/open-island
- open-vibe-island 镜像 (gitcode)：https://gitcode.com/gh_mirrors/op/open-vibe-island
- VibeIsland 工具集评测：https://nimbalyst.com/blog/best-vibe-coding-tools-2026/
