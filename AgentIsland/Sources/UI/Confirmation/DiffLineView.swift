import SwiftUI

struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text("\(line.lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 8)

            Text(prefix)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(lineColor)

            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(lineColor)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 1)
        .background(lineBackground)
    }

    private var prefix: String {
        switch line.type {
        case .added: "+ "
        case .removed: "- "
        case .context: "  "
        }
    }

    private var lineColor: Color {
        switch line.type {
        case .added: DesignTokens.diffAdded
        case .removed: DesignTokens.diffRemoved
        case .context: DesignTokens.textSecondary
        }
    }

    private var lineBackground: Color {
        switch line.type {
        case .added: DesignTokens.diffAdded.opacity(0.1)
        case .removed: DesignTokens.diffRemoved.opacity(0.1)
        case .context: .clear
        }
    }
}
