# UI 组件实现规格

从 design.md 提取的可执行参数，开发时直接参照。

---

## 1. 设计 Token（颜色常量）

```swift
enum DesignTokens {
    // 背景
    static let compactBarBackground = Color(hex: "#000000")
    static let panelBackground = Color(hex: "#1C1C1E")
    static let cardBackground = Color(hex: "#2C2C2E")
    static let cardHover = Color(hex: "#3A3A3C")
    static let separator = Color(hex: "#3A3A3C")
    
    // 状态色
    static let statusIdle = Color(hex: "#8E8E93")
    static let statusThinking = Color(hex: "#0A84FF")
    static let statusExecuting = Color(hex: "#0A84FF")
    static let statusCompleted = Color(hex: "#30D158")
    static let statusWaiting = Color(hex: "#FF9F0A")
    static let statusError = Color(hex: "#FF453A")
    
    // Agent 标签色
    static let tagClaude = Color(hex: "#D97757")
    static let tagCodex = Color(hex: "#10A37F")
    static let tagQoderWork = Color(hex: "#0A84FF")
    static let tagGemini = Color(hex: "#4285F4")
    static let tagTerminal = Color(hex: "#6E6E73")
    
    // 文字
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "#8E8E93")
    static let textCode = Color(hex: "#30D158")
}
```

---

## 2. 字体规格

| 用途 | 字体 | 字号 | 字重 |
|------|------|------|------|
| 面板标题 | SF Pro Text | 15pt | Semibold |
| 任务名称 | SF Pro Text | 13pt | Medium |
| 副文字/描述 | SF Pro Text | 11pt | Regular |
| 代码/命令 | SF Mono | 11pt | Regular |
| 状态文案（缩小态） | SF Pro Text | 12pt | Medium |
| 快捷键标签 | SF Mono | 10pt | Medium |
| 标签（Agent/终端） | SF Pro Text | 11pt | Medium |

---

## 3. 缩小态 (CompactBar)

| 参数 | 值 |
|------|-----|
| 高度 | 32pt |
| 宽度 | 自适应 180-300pt |
| 内边距 | 水平 12pt |
| 圆角 | 左侧 16pt（右侧贴合刘海为 0） |
| 背景 | 纯黑 #000000 |
| 图标尺寸 | 16x16pt |
| 状态文案字体 | SF Pro Text Medium 12pt |

**图标动画规则：**
- 空闲：静止，灰色
- 思考中：左右微摆，0.8s 循环，蓝色
- 执行中：像素流动，0.5s 循环，蓝色
- 已完成：静止，绿色
- 等待确认：脉冲，1s 循环，橙色

---

## 4. 扩展态面板 (ExpandedPanel)

| 参数 | 值 |
|------|-----|
| 最大高度 | 560pt |
| 最大宽度 | 640pt |
| 背景 | #1C1C1E |
| 圆角 | 底部 12pt |
| 阴影 | 0 4px 24px rgba(0,0,0,0.5) |
| 展开动画 | spring(response: 0.3, dampingFraction: 0.85) |
| 收起动画 | easeOut, 250ms |

---

## 5. 任务卡片 (TaskCard)

| 参数 | 值 |
|------|-----|
| 高度 | 44-60pt |
| 状态点 | 圆形 8pt，颜色随状态 |
| 标签样式 | 圆角胶囊，背景 #3A3A3C，文字 12pt |
| 行间距 | 1pt 分割线 #3A3A3C |
| hover 背景 | #3A3A3C |
| 出现动画 | 从右滑入 + 渐显，200ms easeOut |

---

## 6. 权限审批面板

| 参数 | 值 |
|------|-----|
| 代码区字体 | SF Mono 11pt |
| 代码区背景 | #2C2C2E，圆角 8pt |
| 删除行颜色 | #FF453A |
| 新增行颜色 | #30D158 |
| 行号颜色 | #8E8E93 |
| 按钮高度 | 44pt |
| 按钮圆角 | 8pt |
| Deny 按钮 | 背景 #3A3A3C，白色文字 |
| Allow 按钮 | 白色背景，黑色文字 |
| 快捷键 | Deny=Cmd+N, Allow=Cmd+Y |

---

## 7. 选择题面板

| 参数 | 值 |
|------|-----|
| 选项卡片高度 | 44pt |
| 选项卡片背景 | #1E3A3A（深青色） |
| 选项圆角 | 8pt |
| 快捷键标签背景 | #3A3A3C |
| hover 效果 | 亮度 +10% |
| 快捷键映射 | Cmd+1 ~ Cmd+9 |

---

## 8. 动画常量

```swift
enum AnimationConstants {
    static let panelExpand = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let panelCollapse = Animation.easeOut(duration: 0.25)
    static let statusTransition = Animation.easeInOut(duration: 0.2)
    static let cardAppear = Animation.easeOut(duration: 0.2)
    static let confirmationSwitch = Animation.easeInOut(duration: 0.2)
    static let hoverHighlight = Animation.linear(duration: 0.1)
    
    static let hoverDelay: TimeInterval = 0.15
    static let autoReminderDuration: TimeInterval = 5.0
}
```

---

## 9. 设置面板

| 参数 | 值 |
|------|-----|
| 窗口尺寸 | 720 x 560pt（固定） |
| 左侧导航宽度 | 约 200pt |
| 风格 | macOS 系统设置风格 (NSToolbarStyle) |
| 控件 | 原生 Toggle / Slider / Picker |
| 主标题字体 | SF Pro Text 13pt |
| 描述字体 | SF Pro Text 11pt 灰色 |
