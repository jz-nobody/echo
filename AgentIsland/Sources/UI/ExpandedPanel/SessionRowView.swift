import SwiftUI

struct SessionRowView: View {
    let session: AgentSession
    var onTap: (() -> Void)? = nil
    var onAddToFilter: ((String) -> Void)? = nil
    var onRevokeAutoApprove: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var autoApproveHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            userPromptLine
            agentActionLine
            compressedIndicator
            statusSubtitle

            if let todos = session.todos, !todos.isEmpty {
                TaskSectionView(todos: todos)
                    .padding(.leading, 6)
            }

            if let subagents = session.subagents, !subagents.isEmpty {
                SubagentSectionView(subagents: subagents)
                    .padding(.leading, 6)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 0)
        .padding(.trailing, 6)
        .background(isHovered ? DesignTokens.cardHover : DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(AnimationConstants.hoverHighlight) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture { onTap?() }
        .contextMenu {
            Button("添加到过滤") {
                onAddToFilter?(session.title)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sessionAccessibilityLabel)
        .accessibilityHint(onTap != nil ? "Double tap to jump to terminal" : "")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 2) {
            HStack(spacing: -8) {
                PetAnimationView(status: session.status, size: DesignTokens.petSizeExpanded)
                    .frame(width: DesignTokens.petSizeExpanded, height: DesignTokens.petSizeExpanded)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                StatusAnimationView(status: session.status, size: DesignTokens.statusIndicatorSize)
                    .frame(width: DesignTokens.statusIndicatorSize, height: DesignTokens.statusIndicatorSize)
            }
            .offset(x: -4)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: showsInlineStatus ? 13 : 14,
                                  weight: showsInlineStatus ? .medium : .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let text = inlineStatusText {
                    Text(text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(inlineStatusColor)
                }
            }
            .layoutPriority(1)

            if let desc = session.sessionDescription {
                Text(desc)
                    .font(.system(size: showsInlineStatus ? 13 : 14,
                                  weight: showsInlineStatus ? .medium : .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            autoApproveTag

            agentTypeTag

            if let terminal = session.terminalInfo {
                terminalTag(terminal)
            }

            timeTag
        }
    }

    // MARK: - User Prompt

    @ViewBuilder
    private var userPromptLine: some View {
        if let prompt = session.lastUserPrompt {
            HStack(alignment: .top, spacing: 4) {
                Text("你：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize()
                Text(prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(.leading, 6)
        }
    }

    // MARK: - Agent Action

    @ViewBuilder
    private var agentActionLine: some View {
        if let tool = session.currentToolCall {
            (agentPrefix + toolCallText(tool))
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.leading, 6)
        } else if let reply = session.lastAssistantMessage {
            (agentPrefix + Text(reply)
                .font(.system(size: 11))
                .foregroundColor(DesignTokens.textSecondary))
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.leading, 6)
        }
    }

    private var agentPrefix: Text {
        Text("\(agentLabel)：")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(tagColor)
    }

    private func toolCallText(_ tool: String) -> Text {
        let parts = tool.split(separator: " ", maxSplits: 1)
        let toolName = String(parts[0]).replacingOccurrences(of: ":", with: "")
        let toolArgs = parts.count > 1 ? " " + String(parts[1]) : ""

        let nameColor: Color = switch toolName {
        case "Bash": DesignTokens.toolBash
        case "Write", "Edit": DesignTokens.toolWrite
        case "Read": DesignTokens.toolRead
        default: DesignTokens.textSecondary
        }

        return Text(toolName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(nameColor)
        + Text(toolArgs)
            .font(.system(size: 11))
            .foregroundColor(DesignTokens.textSecondary)
    }

    // MARK: - Status Subtitle

    @ViewBuilder
    private var statusSubtitle: some View {
        switch session.status {
        case .idle, .executing, .compacting, .waitingConfirmation:
            EmptyView()
        case .reading:
            statusLabel("查询中", color: DesignTokens.statusReading)
        case .editing:
            statusLabel("编辑中", color: DesignTokens.statusEditing)
        case .thinking:
            statusLabel("思考中", color: DesignTokens.statusThinking)
        case .completed:
            statusLabel("已完成", color: DesignTokens.statusCompleted)
        case .error(let msg):
            statusLabel("错误: \(msg)", color: DesignTokens.statusError)
        }
    }

    private func statusLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.leading, 6)
    }

    // MARK: - Compressed Indicator

    private var shouldShowCompressedTag: Bool {
        guard session.isConversationCompressed,
              let compressedAt = session.compressedAt else { return false }
        return Date().timeIntervalSince(compressedAt) < 30
    }

    @ViewBuilder
    private var compressedIndicator: some View {
        if shouldShowCompressedTag {
            HStack(spacing: 4) {
                Image(systemName: "circle.slash")
                    .font(.system(size: 10))
                Text("对话已压缩")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DesignTokens.statusError)
            .padding(.leading, 6)
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var autoApproveTag: some View {
        if let mode = session.permissionMode, mode != "default" {
            HStack(spacing: 4) {
                Text("自动批准")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.tagAutoApproveBackground)
                if autoApproveHovered {
                    Button {
                        onRevokeAutoApprove?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(DesignTokens.tagAutoApproveBackground)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("取消自动批准")
                }
            }
            .frame(height: 18)
            .padding(.horizontal, 5)
            .background(DesignTokens.tagAutoApproveBackground.opacity(0.15))
            .clipShape(Capsule())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    autoApproveHovered = hovering
                }
            }
        }
    }

    private var agentTypeTag: some View {
        Text(agentLabel)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: 18)
            .padding(.horizontal, 5)
            .background(tagColor)
            .clipShape(Capsule())
    }

    private func terminalTag(_ info: TerminalInfo) -> some View {
        Text(terminalLabel(info))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(height: 18)
            .padding(.horizontal, 5)
            .background(DesignTokens.tagTerminalBackground)
            .clipShape(Capsule())
    }

    private var timeTag: some View {
        Text(relativeTime)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(height: 18)
            .padding(.horizontal, 5)
            .background(DesignTokens.textSecondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private var relativeTime: String {
        let elapsed = Date().timeIntervalSince(session.startTime)
        if elapsed < 60 { return "<1m" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h" }
        return "\(Int(elapsed / 86400))d"
    }

    // MARK: - Helpers

    private var agentLabel: String {
        AgentColorRegistry.shared.label(for: session.agentType)
    }

    private var tagColor: Color {
        AgentColorRegistry.shared.color(for: session.agentType)
    }

    private var sessionAccessibilityLabel: String {
        var parts = ["\(session.title)", "\(session.status.displayText)", "\(agentLabel)"]
        if let prompt = session.lastUserPrompt { parts.append("prompt \(prompt)") }
        if let tool = session.currentToolCall { parts.append("running \(tool)") }
        else if let reply = session.lastAssistantMessage { parts.append("reply \(reply)") }
        if let terminal = session.terminalInfo { parts.append("in \(terminalLabel(terminal))") }
        return parts.joined(separator: ", ")
    }

    private func terminalLabel(_ info: TerminalInfo) -> String {
        switch info.appName {
        case "claude-vscode": "VS Code"
        case "cli": "Terminal"
        default: info.appName
        }
    }

    private var showsInlineStatus: Bool {
        switch session.status {
        case .idle, .executing, .compacting, .waitingConfirmation: return true
        default: return false
        }
    }

    private var inlineStatusText: String? {
        switch session.status {
        case .idle: "就绪"
        case .executing: "运行中"
        case .compacting: "压缩中"
        case .waitingConfirmation: "询问中"
        default: nil
        }
    }

    private var inlineStatusColor: Color {
        switch session.status {
        case .idle: DesignTokens.statusCompleted
        case .executing: DesignTokens.statusExecuting
        case .compacting: DesignTokens.statusCompacting
        case .waitingConfirmation: DesignTokens.statusWaiting
        default: DesignTokens.textSecondary
        }
    }
}
