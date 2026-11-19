import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Палитра (из макета)

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Palette {
    static let background = Color(hex: 0x17181A)
    static let titleBar = Color(hex: 0x202123)
    static let border = Color(hex: 0x2A2C2E)
    static let card = Color(hex: 0x212325)
    static let divider = Color(hex: 0x292C2E)
    static let mint = Color(hex: 0xCCECCC)
    static let muted = Color(hex: 0x9DA3A2)
    static let dim = Color(hex: 0x6F7574)
}

enum Screen { case focus, blocks }

// MARK: - Корневой экран

struct RootView: View {
    @EnvironmentObject var store: FCSStore

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background

            switch store.screen {
            case .focus:
                FocusView(openBlocks: { store.screen = .blocks }, openAdd: { store.showAdd = true })
            case .blocks:
                BlocksView(back: { store.screen = .focus }, openAdd: { store.showAdd = true })
            }

            TitleBar()
        }
        .frame(width: store.screen == .focus ? 404 : 540,
               height: store.screen == .focus ? 386 : 540)
        .ignoresSafeArea()
        .background(WindowConfigurator())
        .sheet(isPresented: $store.showAdd) {
            AddBlockSheet(close: { store.showAdd = false }).environmentObject(store)
        }
        .preferredColorScheme(.dark)
    }
}

struct TitleBar: View {
    var body: some View {
        ZStack {
            Palette.titleBar
            Text("fcs.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.muted)
        }
        .frame(height: 40)
        .overlay(alignment: .bottom) { Palette.border.frame(height: 1) }
        .allowsHitTesting(false)
    }
}

/// Тёмное окно, перетаскивание за фон, без кнопки «развернуть».
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(red: 0x17 / 255.0, green: 0x18 / 255.0, blue: 0x1A / 255.0, alpha: 1)
            w.standardWindowButton(.zoomButton)?.isEnabled = false
            w.title = "FCS"
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Экран «Фокус»

struct FocusView: View {
    @EnvironmentObject var store: FCSStore
    let openBlocks: () -> Void
    let openAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 78)

            FCSLogo()
                .fill(store.isActive ? Palette.mint : Palette.muted)
                .frame(width: 44, height: 43)
                .animation(.easeInOut(duration: 0.25), value: store.isActive)

            Color.clear.frame(height: 42)

            timerRow

            Color.clear.frame(height: 22)

            Button(action: store.toggle) {
                Text(store.isActive ? "Остановить блокировку" : "Начать блокировку")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Palette.mint)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(store.busy)
            .opacity(store.busy ? 0.6 : 1)

            Color.clear.frame(height: 20)

            Button(action: openAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .regular))
                    Text("Добавить блокировку").font(.system(size: 11))
                }
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Color.clear.frame(height: 40)

            Button(action: openBlocks) {
                Text("Блокировки · \(store.totalBlocks)")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.muted)
            }
            .buttonStyle(.plain)

            if let error = store.errorText {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: 0xE08A8A))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 53)
    }

    private var timerRow: some View {
        HStack {
            Text("Таймер")
                .font(.system(size: 12))
                .foregroundColor(Palette.muted)
            Spacer()
            if store.isActive {
                if let remaining = store.remaining {
                    Text(Self.format(remaining))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundColor(.white)
                } else {
                    Text(TimerOption.unlimited.title)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
            } else {
                Menu {
                    ForEach(TimerOption.allCases) { option in
                        Button(option.title) { store.duration = option }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.duration.title).font(.system(size: 13))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(height: 20)
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Экран «Блокировки»

struct BlocksView: View {
    @EnvironmentObject var store: FCSStore
    let back: () -> Void
    let openAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 56)

            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
                    Text("Фокус").font(.system(size: 11))
                }
                .foregroundColor(Palette.muted)
            }
            .buttonStyle(.plain)

            HStack {
                Text("Блокировки")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Button(action: openAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 10))
                        Text("Добавить блокировку").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Palette.mint)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            if store.isActive {
                Text("Во время блокировки список можно только дополнять")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.dim)
                    .padding(.top, 6)
            }

            HStack(alignment: .top, spacing: 14) {
                card(title: "Сайты", count: store.sites.count) {
                    ForEach(store.sites, id: \.self) { site in
                        row(site, compact: true) { store.removeSite(site) }
                    }
                }
                .frame(width: 279)

                card(title: "Приложения", count: store.apps.count) {
                    ForEach(store.apps) { app in
                        row(app.name, compact: false) { store.removeApp(app) }
                        if app != store.apps.last { Palette.divider.frame(height: 1) }
                    }
                }
                .frame(width: 199)
            }
            .padding(.top, store.isActive ? 12 : 26)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 30)
    }

    private func card<Content: View>(title: String, count: Int,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("\(count)").font(.system(size: 11)).foregroundColor(Palette.muted)
            }
            .padding(.bottom, 12)

            Palette.divider.frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) { content() }
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(maxHeight: 340, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ title: String, compact: Bool, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            Button(action: remove) {
                Text("—").font(.system(size: 12)).foregroundColor(Palette.muted)
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isActive)
            .opacity(store.isActive ? 0.25 : 1)
            .help(store.isActive ? "Нельзя удалять во время блокировки" : "Удалить")
        }
        .padding(.vertical, compact ? 1.5 : 9)
    }
}

// MARK: - Добавление блокировки

enum BlockKind: String, CaseIterable { case site = "Сайт", app = "Приложение" }

final class AddModel: ObservableObject {
    @Published var kind: BlockKind = .site
    @Published var siteText = ""
    @Published var pickedApp: BlockedApp?
    @Published var error: String?
}

struct AddBlockSheet: View {
    @EnvironmentObject var store: FCSStore
    @StateObject private var model = AddModel()
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Добавить блокировку")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Picker("", selection: $model.kind) {
                ForEach(BlockKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.kind {
            case .site:
                TextField("example.com", text: $model.siteText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
            case .app:
                HStack {
                    Button("Выбрать приложение…", action: chooseApp)
                    if let app = model.pickedApp {
                        Text(app.name).font(.system(size: 12)).foregroundColor(Palette.muted)
                    }
                }
            }

            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundColor(Color(hex: 0xE08A8A))
            }

            HStack {
                Spacer()
                Button("Отмена") { close() }
                    .keyboardShortcut(.cancelAction)
                Button(action: add) {
                    Text("Добавить")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.background)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Palette.mint)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 340)
        .background(Palette.titleBar)
        .preferredColorScheme(.dark)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Выберите приложение для блокировки"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            model.error = "Не удалось определить приложение"
            return
        }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        model.pickedApp = BlockedApp(name: name, bundleID: id)
        model.error = nil
    }

    private func add() {
        switch model.kind {
        case .site:
            if let e = store.addSite(model.siteText) { model.error = e } else { close() }
        case .app:
            guard let app = model.pickedApp else { model.error = "Сначала выберите приложение"; return }
            if let e = store.addApp(app) { model.error = e } else { close() }
        }
    }
}
