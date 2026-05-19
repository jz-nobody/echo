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

### 3. 实施
- 每个逻辑变更一次 commit
- 保持文件 < 200 行
- 不跨 Step 实现功能

### 4. 验证
- `xcodebuild build` 编译通过（有 Xcode 项目后）
- 单元测试通过
- 手动验证匹配验收标准
- 无 warning 无 force unwrap

### 5. 收尾
- 创建/更新当天 `devlog/YYYY-MM-DD.md`
- 更新 `project.md` 的里程碑状态
- Git commit（pre-commit hook 会检查 devlog）

---

## Git 分支策略

- `main` — 始终可编译可运行
- `step/N-description` — 每个 Step 的开发分支
- Step 验证通过后合并到 main

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
