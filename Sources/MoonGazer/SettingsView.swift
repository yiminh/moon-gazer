import SwiftUI

/// The preferences window. Uses the native system UI font (not the dashboard theme)
/// for a familiar, modern macOS feel.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var section: Section = .templates

    enum Section: String, CaseIterable, Identifiable {
        case templates = "Templates", appearance = "Appearance", typography = "Typography",
             colors = "Colors", layout = "Layout"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .templates: return "square.grid.2x2"
            case .appearance: return "circle.lefthalf.filled"
            case .typography: return "textformat"
            case .colors: return "paintpalette"
            case .layout: return "rectangle.split.3x1"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .templates: TemplatesSection(settings: settings)
                    case .appearance: AppearanceSection(settings: settings)
                    case .typography: TypographySection(settings: settings)
                    case .colors: ColorsSection(settings: settings)
                    case .layout: LayoutSection(settings: settings)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

// MARK: - Section header

private struct SectionTitle: View {
    let title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
    }
}

// MARK: - Templates

private struct TemplatesSection: View {
    @ObservedObject var settings: AppSettings
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Templates", subtitle: "A starting look. Pick one, then fine-tune anything.")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Template.allCases) { t in
                    TemplateCard(t: t, selected: settings.template == t) { settings.applyTemplate(t) }
                }
            }
        }
    }
}

private struct TemplateCard: View {
    let t: Template
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let s = t.spec
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                // Mini preview: background + accent trio + a couple of bars.
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.fromHex(s.darkBg))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            ForEach([s.claude, s.codex, s.omlx], id: \.self) { hex in
                                Circle().fill(Color.fromHex(hex)).frame(width: 9, height: 9)
                            }
                        }
                        Capsule().fill(Color.fromHex(s.claude)).frame(width: 70, height: 5)
                        Capsule().fill(Color.fromHex(s.codex)).frame(width: 46, height: 5)
                    }
                    .padding(12)
                }
                .frame(height: 74)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))

                Text(t.title).font(.headline)
                Text(t.blurb).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(selected ? 0.06 : 0.03)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Appearance", subtitle: "Light, dark, or follow the system.")
            Card {
                Picker("", selection: $settings.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

// MARK: - Typography

private struct TypographySection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Typography", subtitle: "Fonts for body text and the big numbers, each with its own weight.")
            Card {
                fontRow("Body font", selection: $settings.bodyTypeface, bold: $settings.bodyBold)
                Divider()
                fontRow("Number font", selection: $settings.numberTypeface, bold: $settings.numberBold)
            }
            Card {
                Text("PREVIEW").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).tracking(1.5)
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("47").font(settings.numberTypeface.font(size: 44, weight: settings.numberBold ? .bold : .light))
                    Text("%").font(settings.numberTypeface.font(size: 20, weight: settings.numberBold ? .bold : .light))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Weekly 7d").font(settings.bodyTypeface.font(size: 14, weight: settings.bodyBold ? .semibold : .medium))
                        Text("resets in 3d 4h").font(settings.bodyTypeface.font(size: 11, weight: .regular)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func fontRow(_ label: String, selection: Binding<Typeface>, bold: Binding<Bool>) -> some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            Picker("", selection: selection) {
                ForEach([Typeface.Category.mono, .serif, .sans], id: \.self) { cat in
                    SwiftUI.Section(header: Text(cat.rawValue)) {
                        ForEach(Typeface.allCases.filter { $0.category == cat }) { Text($0.title).tag($0) }
                    }
                }
            }
            .labelsHidden()
            Toggle("Bold", isOn: bold).toggleStyle(.checkbox)
        }
    }
}

// MARK: - Colors

private struct ColorsSection: View {
    @ObservedObject var settings: AppSettings

    private var alertsEnabled: Bool { settings.barColorMode.usesAlertColors }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Colors", subtitle: "Accent per pane, plus how bars react as usage climbs.")

            Card {
                Text("BAR BEHAVIOR").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).tracking(1.5)
                Picker("", selection: $settings.barColorMode) {
                    ForEach(BarColorMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.radioGroup)
            }

            Card {
                Text("ACCENT").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).tracking(1.5)
                ColorField(label: "Claude", hex: $settings.claudeAccentHex)
                ColorField(label: "Codex", hex: $settings.codexAccentHex)
                ColorField(label: "OMLX", hex: $settings.omlxAccentHex)
            }

            Card {
                HStack {
                    Text("ALERT COLORS & THRESHOLDS").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).tracking(1.5)
                    Spacer()
                    if !alertsEnabled {
                        Text("disabled in “Accent only”").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                ColorField(label: "Warning", hex: $settings.warnHex).disabled(!alertsEnabled)
                thresholdRow("Warn at", value: $settings.warnThreshold, range: 40...95)
                    .disabled(!alertsEnabled)
                ColorField(label: "Danger", hex: $settings.dangerHex).disabled(!alertsEnabled)
                thresholdRow("Danger at", value: $settings.dangerThreshold, range: 60...100)
                    .disabled(!alertsEnabled)
            }
            .opacity(alertsEnabled ? 1 : 0.5)
        }
    }

    private func thresholdRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))%").monospacedDigit().frame(width: 42, alignment: .trailing)
        }
    }
}

/// A reusable colour control: swatch + hex field + a popover of 32 curated presets
/// and a native colour wheel.
struct ColorField: View {
    let label: String
    @Binding var hex: String
    @State private var showPicker = false
    @State private var draft = ""

    private var color: Color { Color(hex: hex) ?? .gray }

    var body: some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 90, alignment: .leading)
            Spacer()
            TextField("#RRGGBB", text: $draft)
                .textFieldStyle(.roundedBorder).frame(width: 100)
                .font(.system(.body, design: .monospaced))
                .onSubmit { if Color(hex: draft) != nil { hex = draft.uppercased() } }
                .onAppear { draft = hex }
                .onChange(of: hex) { _, newValue in draft = newValue }
            Button { showPicker.toggle() } label: {
                RoundedRectangle(cornerRadius: 6).fill(color)
                    .frame(width: 34, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker) { PresetPopover(hex: $hex) }
        }
    }
}

private struct PresetPopover: View {
    @Binding var hex: String
    private let cols = Array(repeating: GridItem(.fixed(26), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker("Custom", selection: Binding(
                get: { Color(hex: hex) ?? .gray },
                set: { hex = $0.hexString }))
            .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)

            group("For dark backgrounds", Presets.dark)
            group("For light backgrounds", Presets.light)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func group(_ title: String, _ colors: [PresetColor]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(colors) { c in
                    Button { hex = c.hex } label: {
                        Circle().fill(Color.fromHex(c.hex)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary.opacity(hex.uppercased() == c.hex ? 0.9 : 0.12),
                                                     lineWidth: hex.uppercased() == c.hex ? 2 : 1))
                    }
                    .buttonStyle(.plain).help(c.name)
                }
            }
        }
    }
}

// MARK: - Layout

private struct LayoutSection: View {
    @ObservedObject var settings: AppSettings

    private var disabled: [Pane] { Pane.allCases.filter { !settings.columns.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Layout", subtitle: "Which columns to show, left to right. Reorder or hide any.")
            Card {
                Text("SHOWN (left → right)").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).tracking(1.5)
                if settings.columns.isEmpty {
                    Text("No columns — add one below.").foregroundStyle(.secondary).font(.callout)
                }
                ForEach(Array(settings.columns.enumerated()), id: \.element) { index, pane in
                    HStack {
                        Text("\(index + 1)").foregroundStyle(.secondary).monospacedDigit().frame(width: 18)
                        Text(pane.title).fontWeight(.medium)
                        Spacer()
                        Button { move(index, -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(index == 0)
                        Button { move(index, 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(index == settings.columns.count - 1)
                        Button { settings.columns.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    }
                    .padding(.vertical, 3)
                    if index < settings.columns.count - 1 { Divider() }
                }
            }
            if !disabled.isEmpty {
                Card {
                    Text("HIDDEN").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).tracking(1.5)
                    ForEach(disabled) { pane in
                        HStack {
                            Text(pane.title).foregroundStyle(.secondary)
                            if pane == .omlx { Text("(needs config)").font(.caption).foregroundStyle(.tertiary) }
                            Spacer()
                            Button { settings.columns.append(pane) } label: {
                                Label("Add", systemImage: "plus.circle")
                            }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func move(_ index: Int, _ delta: Int) {
        let target = index + delta
        guard settings.columns.indices.contains(target) else { return }
        settings.columns.swapAt(index, target)
    }
}
