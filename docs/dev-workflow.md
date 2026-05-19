# 开发工作流

## 每次工作会话流程

### 1. 开始工作
1. 阅读 `devlog/` 最新条目，了解上次完成到哪里
2. 查看 `project.md` 确认当前阶段和阻塞项
3. 确定本次要执行的 Step

### 2. 实施前准备
- 阅读对应的文档：
  - UI 相关 → `design.md` + `docs/ui-component-spec.md`
  - 架构相关 → `arc.md` + `docs/agent-adaptor-protocol.md`
  - 编码 → `docs/swift-standards.md`
- 明确本 Step 的验收标准（见 plan 或 prd.md）
- **设计测试用例**：在编码前先想清楚该模块的测试场景，包括：
  - 正常路径（happy path）
  - 边界条件（空数据、超大数据、并发）
  - 错误场景（网络失败、格式异常）
  - 将测试用例记录在 devlog 中作为开发依据

### 3. 实施
- 每个逻辑变更一次 commit
- 保持文件 < 200 行
- 不跨 Step 实现功能

### 4. 模块化测试验收
- `xcodebuild build` 编译通过
- **单元测试全部通过**（覆盖实施前设计的所有测试用例）
- 手动验证匹配验收标准
- 无 warning 无 force unwrap
- 确认该模块可独立运行，不破坏已有功能（回归验证）

### 5. 收尾
- 创建/更新当天 `devlog/YYYY-MM-DD.md`
- 更新 `project.md` 的里程碑状态
- Git commit（pre-commit hook 会检查 devlog）

---

## Git 分支策略

- `main` — 主分支，始终可编译可运行，只接受通过验证的合并
- `step/N-description` — 每个 Step 的功能分支（如 `step/1-notch-window`）

### 分支工作流

```
1. 开始新 Step 前，从 main 创建功能分支：
   git checkout main
   git checkout -b step/N-description

2. 在功能分支上开发，每个逻辑变更一次 commit

3. 开发完成后运行测试验证：
   - xcodebuild build（编译通过）
   - xcodebuild test（单元测试通过）
   - 手动验证匹配验收标准

4. 验证全部通过后，合并到 main：
   git checkout main
   git merge step/N-description

5. 合并后保留分支（不删除），方便回溯历史
```

### 版本管理原则

- 每次 commit 都是一个可回滚的节点，message 清晰描述变更内容
- 功能分支上允许多次中间 commit，合并到 main 时保留完整历史（不 squash）
- 出现问题时可以 `git revert` 回退单个 commit，或 `git reset` 回退到分支起点
- 每个 Step 合并到 main 后打一个轻量 tag：`git tag step-N-done`

## Commit 消息格式

```
<type>: <subject>

[optional body]
```

type 取值：
- `feat:` 新功能
- `fix:` 修复
- `refactor:` 重构
- `test:` 测试
- `docs:` 文档
- `chore:` 项目配置/脚手架

subject 规则：
- 英文，小写开头
- 不超过 72 字符
- 使用祈使句（"add" 而非 "added"）
