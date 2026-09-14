// Copyright 2026 Yash Chaudhary
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI

/// One executable entry in the ⌘K palette.
struct ZenCommand: Identifiable {
    let id: String
    let title: String
    var subtitle: String?
    let icon: String
    /// Extra lowercase search terms not visible in the row.
    var keywords: String = ""
    let action: () -> Void
}

/// ⌘K command palette: type to filter, ↑↓ to move, ↩ to run, esc to close.
struct ZenCommandPalette: View {
    let commands: [ZenCommand]
    @Binding var query: String
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var matches: [ZenCommand] {
        let terms = query
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        guard !terms.isEmpty else { return commands }
        return commands
            .filter { command in
                let haystack = (
                    command.title + " "
                        + (command.subtitle ?? "") + " "
                        + command.keywords
                ).lowercased()
                return terms.allSatisfy(haystack.contains)
            }
            .sorted { lhs, rhs in
                let query = terms[0]
                let lhsPrefix = lhs.title.lowercased().hasPrefix(query)
                let rhsPrefix = rhs.title.lowercased().hasPrefix(query)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return false
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)

            panel
                .padding(.top, 96)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.98))
                )
        }
        .onAppear { searchFocused = true }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchRow
            Divider().overlay(ZenDesign.Semantic.border)
            results
            Divider().overlay(ZenDesign.Semantic.border)
            footer
        }
        .frame(width: 560)
        .background {
            ZenMaterialSurface(
                material: .popover,
                tint: ZenDesign.Semantic.surface.opacity(0.90),
                fallback: ZenDesign.Semantic.surface
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.large,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.large,
                style: .continuous
            )
            .strokeBorder(ZenDesign.Semantic.borderStrong)
        }
        .shadow(color: .black.opacity(0.30), radius: 28, y: 12)
        .accessibilityAddTraits(.isModal)
    }

    private var searchRow: some View {
        HStack(spacing: ZenDesign.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField("Search settings, models, actions…", text: $query)
                .textFieldStyle(.plain)
                .font(ZenDesign.Typography.body)
                .focused($searchFocused)
                .onSubmit(runHighlighted)
                .onExitCommand(perform: dismiss)
                .onKeyPress(.downArrow) {
                    move(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
                .accessibilityLabel("Search commands")
            ZenKbd(text: "esc")
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .frame(height: 44)
        .onChange(of: query) { _, _ in
            highlighted = 0
        }
    }

    @ViewBuilder
    private var results: some View {
        if matches.isEmpty {
            Text("No matching command")
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ZenDesign.Spacing.lg)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(matches.enumerated()),
                            id: \.element.id
                        ) { index, command in
                            commandRow(command, index: index)
                                .id(command.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 322)
                .onChange(of: highlighted) { _, index in
                    guard matches.indices.contains(index) else {
                        return
                    }
                    proxy.scrollTo(matches[index].id)
                }
            }
        }
    }

    private func commandRow(
        _ command: ZenCommand,
        index: Int
    ) -> some View {
        Button {
            run(command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: command.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(ZenDesign.Semantic.surfaceRaised)
                    }
                    .accessibilityHidden(true)
                Text(command.title)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if index == highlighted {
                    ZenKbd(text: "↩")
                }
            }
            .padding(.horizontal, ZenDesign.Spacing.sm)
            .frame(minHeight: ZenDesign.Layout.hitTarget)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    index == highlighted
                        ? ZenDesign.Semantic.surfaceRaised
                        : Color.clear
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ZenPressButtonStyle())
        .onHover { hovering in
            if hovering {
                highlighted = index
            }
        }
        .accessibilityLabel(command.title)
    }

    private var footer: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            hint(keys: ["↑", "↓"], label: "navigate")
            hint(keys: ["↩"], label: "open")
            hint(keys: ["esc"], label: "close")
            Spacer()
            Text("\(matches.count) results")
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .frame(height: 32)
        .background(ZenDesign.Semantic.surfaceRaised.opacity(0.4))
    }

    private func hint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(ZenDesign.Typography.monoSmall)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(ZenDesign.Semantic.border)
                    }
            }
            Text(label)
                .font(ZenDesign.Typography.monoSmall)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .accessibilityHidden(true)
    }

    private func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        highlighted = min(
            max(0, highlighted + delta),
            matches.count - 1
        )
    }

    private func runHighlighted() {
        guard matches.indices.contains(highlighted) else { return }
        run(matches[highlighted])
    }

    private func run(_ command: ZenCommand) {
        command.action()
        dismiss()
    }
}
