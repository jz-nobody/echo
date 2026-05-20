import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var store: SettingsStore
    @State private var newKeyword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通知过滤").font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "内置规则")
                    SettingsToggleRow(
                        title: "启用内置过滤",
                        isOn: $store.enableBuiltInFilters
                    )
                    if store.enableBuiltInFilters {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(SessionFilter.builtInPatterns, id: \.self) { pattern in
                                HStack {
                                    Image(systemName: "line.horizontal.3.decrease.circle")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text(pattern)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader(title: "自定义关键词")
                    Text("标题包含以下关键词的会话将被隐藏")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("输入关键词", text: $newKeyword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .onSubmit { addKeyword() }
                        Button("添加") { addKeyword() }
                            .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !store.filterKeywords.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(store.filterKeywords.enumerated()), id: \.offset) { index, keyword in
                                HStack {
                                    Text(keyword)
                                        .font(.system(size: 11, design: .monospaced))
                                    Spacer()
                                    Button {
                                        removeKeyword(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !store.filterKeywords.contains(trimmed) else { return }
        store.filterKeywords.append(trimmed)
        newKeyword = ""
    }

    private func removeKeyword(at index: Int) {
        guard store.filterKeywords.indices.contains(index) else { return }
        store.filterKeywords.remove(at: index)
    }
}
