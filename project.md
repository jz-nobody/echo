# Agent Island - 项目进展文档

> 最后更新：2026-05-20

---

## 当前阶段：Phase 3 — 体验完善

Phase 1-2 全部完成（Steps 0-12, 95 tests, E2E 验证通过）。Phase 3 设置基础设施已完成（Steps 13-14, 106 tests）。

---

## 里程碑进度

| 里程碑 | 状态 | 完成日期 | 备注 |
|--------|------|---------|------|
| 产品方向确定 | ✅ 完成 | 2026-05-19 | 确定做 VibeIsland 竞品，刘海区多 Agent 聚合器 |
| 竞品研究 | ✅ 完成 | 2026-05-19 | VibeIsland 全功能分析 + 开源替代研究 |
| QoderWork MCP API 验证 | ✅ 完成 | 2026-05-19 | 127.0.0.1:52345，17 个工具全部可用 |
| 技术可行性评估 | ✅ 完成 | 2026-05-20 | 全部核心技术点评级"高可行性" |
| PRD 文档 | ✅ 完成 | 2026-05-20 | 11 个功能点 + 验收标准 |
| 交互视觉方案 | ✅ 完成 | 2026-05-20 | 1:1 参考 VibeIsland |
| 架构设计 | ✅ 完成 | 2026-05-20 | Pure Swift 技术栈锁定 |
| Phase 1: 壳子 + 单 Agent | ✅ 完成 | 2026-05-20 | Step 0-8 全部完成，64 tests |
| Phase 2: 多 Agent 接入 | ✅ 完成 | 2026-05-20 | Claude Code 适配器完成，E2E 验证通过，95 tests |
| Phase 3: 体验完善 | 🔄 进行中 | - | Step 13-14 设置基础完成，106 tests |
| Phase 4: 稳定化 | 🔲 未开始 | - | 目标：测试覆盖 + 性能优化 |

---

## 当前阻塞项

### 1. Claude Code 日志格式 ✅ 已验证
- **描述**：已验证 Claude Code 日志系统
- **结果**：Session 状态文件在 `~/.claude/sessions/<pid>.json`，会话 JSONL 在 `~/.claude/projects/<path>/<sessionId>.jsonl`，审计日志在 `~/.claude/audit/audit.jsonl`
- **方案**：通过 PermissionRequest hook + Unix socket IPC 实现权限拦截，不解析 JSONL（太复杂）
- **状态**：已解决

### 2. Codex 日志格式未知
- **描述**：Codex CLI 的本地日志路径和格式完全未知
- **影响**：CodexAdaptor 需要从零逆向
- **解决方案**：安装 Codex 后观察其在 `~/` 下创建的文件和进程行为
- **优先级**：中（不影响 Phase 1）

### 3. open-vibe-island 源码未能获取
- **描述**：GitHub 访问超时，无法查阅开源替代的具体实现代码
- **影响**：无法参考其终端 hook 和 PTY 注入的具体实现方式
- **解决方案**：通过 VPN 或 GitHub mirror 重新获取；或独立实现
- **优先级**：低（可参考但非必须）

---

## 下一步行动

### 立即可执行（Phase 1 启动条件已具备）

1. **创建 Xcode 项目**
   - 新建 macOS App 项目，SwiftUI 生命周期
   - 配置 SPM 依赖（暂无外部依赖）
   - 设置 .gitignore 和初始仓库

2. **实现 WindowController**
   - 无边框 NSPanel 创建
   - 刘海区尺寸检测和窗口定位
   - NSTrackingArea hover 监听
   - 展开/收起动画

3. **实现 QoderWorkAdaptor**
   - MCPClient 封装（JSON-RPC 2.0 over HTTP）
   - qoder_list_tasks 调用
   - qoder_get_task_detail 轮询
   - qoder_respond_task 确认提交

4. **实现基础 UI**
   - CompactBarView（缩小态）
   - ExpandedPanelView（扩展态 - 任务列表）
   - ConfirmationView（确认面板 - 权限审批 + 选择题）

---

## 已验证的技术假设

| 假设 | 验证结果 | 验证方式 |
|------|---------|---------|
| QoderWork MCP 可通过 HTTP 访问 | ✅ 确认 | curl 调用 127.0.0.1:52345 |
| MCP tools/list 返回任务管理工具 | ✅ 确认 | 返回 17 个工具 |
| qoder_get_task_detail 可获取 tool call state | ✅ 确认 | state: call/input-streaming/result |
| qoder_respond_task 支持 approve/deny/answer | ✅ 确认 | 文档确认 |
| 无边框置顶窗口可嵌入刘海区 | ✅ 确认 | VibeIsland + open-vibe-island 验证 |
| 终端 hook 可监听 Agent 输出 | ✅ 确认 | VibeIsland 生产环境验证 |
| Accessibility API 可实现窗口跳转 | ✅ 确认 | macOS 标准 API，多产品使用 |

---

## 风险登记

| 编号 | 风险描述 | 可能性 | 影响 | 缓解策略 | 状态 |
|------|---------|--------|------|---------|------|
| R-001 | Claude Code 更新改变日志格式 | 中 | 高 | 模块化解析器，支持多版本 | 监控 |
| R-002 | macOS 15+ 改变窗口层级行为 | 低 | 高 | 关注 WWDC，提前适配 | 监控 |
| R-003 | QoderWork MCP 端口变更 | 低 | 中 | 支持端口配置和自动探测 | 接受 |
| R-004 | 辅助功能权限用户拒绝 | 中 | 中 | 功能优雅降级 + 引导文案 | 接受 |
| R-005 | 与 VibeIsland 功能高度重叠 | 高 | 中 | 差异化：QoderWork 原生支持 + 国内 Agent | 主动应对 |
