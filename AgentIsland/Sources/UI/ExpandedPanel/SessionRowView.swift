import SwiftUI

struct SessionRowView: View {
    let session: AgentSession
    var onTap: (() -> Void)? = nil
    var onAddToFilter: ((String) -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            userPromptLine
            agentActionLine
            compressedIndicator
            statusSubtitle

            if let todos = session.todos, !todos.isEmpty {
                TaskSectionView(todos: todos)
            }

            if let subagents = session.subagents, !subagents.isEmpty {
                SubagentSectionView(subagents: subagents)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
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
        HStack(spacing: 6) {
            StatusDotView(status: session.status)

            Text(titleText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            autoApproveTag

            agentTypeTag

            if let terminal = session.terminalInfo {
                terminalTag(terminal)
            }

            timeTag
        }
    }

    private var titleText: String {
        if let desc = session.sessionDescription {
            return "\(session.title) · \(desc)"
        }
        return session.title
    }

    // MARK: - User Prompt

    @ViewBuilder
    private var userPromptLine: some View {
        if let prompt = session.lastUserPrompt {
            HStack(spacing: 4) {
                Text("你：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
        }
    }

    // MARK: - Agent Action

    @ViewBuilder
    private var agentActionLine: some View {
        if let tool = session.currentToolCall {
            toolCallText(tool)
                .lineLimit(1)
                .padding(.leading, 16)
        } else if let reply = session.lastAssistantMessage {
            Text(reply)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)
                .padding(.leading, 16)
        }
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
        if session.status == .idle {
            Text("就绪")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.statusCompleted)
                .padding(.leading, 16)
        } else if session.status == .completed {
            Text("Done — click to jump")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.statusCompleted)
                .padding(.leading, 16)
        }
    }

    // MARK: - Compressed Indicator

    @ViewBuilder
    private var compressedIndicator: some View {
        if session.isConversationCompressed {
            HStack(spacing: 4) {
                Image(systemName: "circle.slash")
                    .font(.system(size: 10))
                Text("对话已压缩")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(DesignTokens.statusError)
            .padding(.leading, 16)
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var autoApproveTag: some View {
        if let mode = session.permissionMode, mode != "default" {
            Text("自动批准 ×")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.tagAutoApproveBackground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignTokens.tagAutoApproveBackground.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var agentTypeTag: some View {
        Text(agentLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor)
            .clipShape(Capsule())
    }

    private func terminalTag(_ info: TerminalInfo) -> some View {
        Text(terminalLabel(info))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignTokens.tagTerminalBackground)
            .clipShape(Capsule())
    }

    private var timeTag: some View {
        Text(relativeTime)
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.textSecondary)
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
        switch session.agentType {
        case .qoderWork: "Qoder"
        case .claudeCode: "Claude"
        case .codex: "Codex"
        }
    }

    private var tagColor: Color {
        switch session.agentType {
        case .qoderWork: DesignTokens.tagQoderWork
        case .claudeCode: DesignTokens.tagClaude
        case .codex: DesignTokens.tagCodex
        }
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
}
