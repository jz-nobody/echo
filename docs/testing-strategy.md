# 测试策略

## 测试金字塔

```
        /  手动验证  \        5%  — UI 视觉、动画流畅度
       / 集成测试     \      15%  — 端到端流程、MCP 真实调用
      / 单元测试        \    80%  — 逻辑、解析、状态机
```

---

## 1. 单元测试

### 覆盖范围
- MCPClient：请求格式化、响应解码、错误处理
- QoderWorkAdaptor：状态映射、数据转换
- SessionManager：会话生命周期、状态聚合、轮询控制
- NotificationQueue：入队、出队、排队顺序、空队列处理
- NotchDetector：坐标计算（可 mock NSScreen）
- Models：编解码、Equatable/Hashable 正确性

### Mock 模式

**网络 Mock：**
```swift
final class MockURLProtocol: URLProtocol {
    static var mockResponses: [URL: (Data, HTTPURLResponse)] = [:]
    // 拦截 URLSession 请求，返回预设响应
}
```

**适配器 Mock：**
```swift
final class MockAgentAdaptor: AgentAdaptor {
    var agentType: AgentType = .qoderWork
    var mockSessions: [AgentSession] = []
    var mockStatus: SessionStatus = .idle
    var mockConfirmations: [PendingConfirmation] = []
    // 用于 UI 测试和 SessionManager 测试
}
```

### 命名规范

```swift
func test_discoverSessions_whenMCPReturnsThreeTasks_returnsThreeSessions() { }
func test_getStatus_whenToolCallStateIsCall_returnsWaitingConfirmation() { }
func test_respond_withAllowResponse_sendsMCPApprove() { }
```

格式：`test_<方法>_<条件>_<预期结果>()`

---

## 2. 集成测试

### 覆盖范围
- MCP 客户端 → 真实 QoderWork 端点（需 QoderWork 运行）
- 完整发现-显示-确认-响应链路
- 错误恢复（断开重连）

### 执行条件
- 标记为 `@Test(.disabled("Requires running QoderWork"))` 在 CI 中跳过
- 本地手动执行时需要先启动 QoderWork

---

## 3. 手动验证

### 每个 Step 的验证清单

**Step 1 (窗口定位)：**
- [ ] 应用启动后 panel 出现在刘海区正确位置
- [ ] panel 始终在最顶层
- [ ] 外接显示器（无刘海）时 fallback 位置合理

**Step 2 (缩小态 UI)：**
- [ ] 视觉匹配 design.md CompactBar 规格
- [ ] 字体、颜色、间距正确
- [ ] 简洁/详细两种模式可切换

**Step 3 (Hover 展开收起)：**
- [ ] hover 0.15s 后平滑展开
- [ ] 移开鼠标平滑收起
- [ ] 快速来回不闪烁
- [ ] ESC 可收起
- [ ] 动画 60fps（无卡顿）

**Step 4 (MCP 客户端)：**
- [ ] 所有单元测试通过
- [ ] 手动调用 tools/list 返回正确结果（需 QoderWork）

**Step 5 (QoderWork 适配器)：**
- [ ] Mock 测试全部通过
- [ ] 真实 QoderWork 任务可被发现和状态获取

**Step 6 (接入 UI)：**
- [ ] 启动 QoderWork 任务后 3s 内面板显示
- [ ] 状态实时更新
- [ ] 空闲时 CPU < 1%

**Step 7 (确认交互)：**
- [ ] 权限审批面板 diff 渲染正确
- [ ] Cmd+Y/N 快捷键可用
- [ ] 选择题面板选项正确显示
- [ ] Cmd+1/2/3 选择可用

**Step 8 (端到端)：**
- [ ] 完整流程跑通无异常
- [ ] 断开/重连正常恢复
- [ ] 30 分钟运行无内存泄漏

---

## 4. 性能验证

使用 Instruments 检查：
- Memory：常驻 < 80MB
- CPU：空闲 < 1%，轮询时 < 3%
- Animation：展开/收起期间 60fps
- Leaks：无内存泄漏

---

## 5. 测试文件组织

```
AgentIsland/Tests/
├── CoreTests/
│   ├── SessionManagerTests.swift
│   └── NotificationQueueTests.swift
├── AdaptorTests/
│   ├── MCPClientTests.swift
│   ├── QoderWorkAdaptorTests.swift
│   └── Mocks/
│       ├── MockURLProtocol.swift
│       └── MockAgentAdaptor.swift
└── InfrastructureTests/
    └── NotchDetectorTests.swift
```
