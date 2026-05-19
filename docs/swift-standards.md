# Swift 编码规范

## 基本规则

- Swift 5.9+，macOS 14+ deployment target
- 4 空格缩进
- 行宽上限 120 字符
- 文件上限 200 行，超过则拆分
- 不写不必要的注释，代码自解释

## 命名规范

- 类型名：UpperCamelCase（`SessionManager`, `CompactBarView`）
- 方法/属性：lowerCamelCase（`discoverSessions()`, `isExpanded`）
- 协议：形容词或 -able 后缀（`AgentAdaptor`）
- 枚举 case：lowerCamelCase（`.waitingConfirmation`）
- 常量：lowerCamelCase（`let maxPanelHeight: CGFloat = 560`）

## 文件组织

```swift
// 1. Imports（分组：系统框架、项目模块）
import SwiftUI
import AppKit

// 2. 类型声明
@Observable
final class SessionManager {
    // 3. 存储属性
    private(set) var sessions: [AgentSession] = []
    
    // 4. 初始化
    init(adaptors: [any AgentAdaptor]) { ... }
    
    // 5. 公开方法
    func startPolling() { ... }
    
    // 6. 私有方法
    private func poll() async { ... }
}

// 7. 协议遵从（用 extension 分离）
extension SessionManager: CustomStringConvertible { ... }
```

## 并发模式

- 使用 `async/await`，不用 completion handler
- UI 变更标记 `@MainActor`
- 后台任务用 `Task { }` 或 `TaskGroup`
- 不使用 DispatchQueue（除非 AppKit 强制要求）

## 状态管理

- 使用 `@Observable`（不用 ObservableObject + @Published）
- 依赖注入通过 SwiftUI `.environment()`
- 不使用单例
- 数据流单向：Adaptor → SessionManager → UI

## 错误处理

- 定义 typed error enum：
  ```swift
  enum MCPError: Error {
      case connectionFailed(URL)
      case invalidResponse(Int)
      case timeout
  }
  ```
- 不用 `try?` 静默吞错
- 网络错误：重试 + 降级
- UI 层：显示用户可理解的状态（如 "Offline"）

## 访问控制

- 默认 `internal`
- 仅暴露给外部模块的标 `public`
- 实现细节标 `private`
- 不用 `open`（不设计为可继承）

## SwiftUI 规范

- View body 保持简洁，复杂逻辑抽为 computed property 或子 View
- 使用 ViewModifier 复用样式
- Preview 使用 `#Preview` 宏
- 颜色使用语义常量（`DesignTokens.statusRunning`），不硬编码 hex

## AppKit 互操作

- SwiftUI 内容通过 `NSHostingView` 嵌入 NSPanel
- NSPanel 配置在 `WindowController` 中集中管理
- NSTrackingArea 事件通过 delegate/callback 传递给 SwiftUI 层

## 禁止事项

- 禁止 force unwrap（`!`）在生产代码中
- 禁止 `import UIKit`
- 禁止 Combine publisher 在新代码中使用（用 @Observable + AsyncStream）
- 禁止 Any / AnyObject 作为方法参数类型
- 禁止硬编码 magic number（使用 DesignTokens 或命名常量）
