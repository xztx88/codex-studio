import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct CodexStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environmentObject(state)
                .frame(minWidth: 1020, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加账号...") {
                    state.isAddModalPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("全部刷新用量") {
                    state.refreshAllQuotas()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

struct MainContainerView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                SidebarView(state: state)

                Divider()

                ZStack {
                    switch state.selectedTab {
                    case .overview:
                        OverviewView(state: state)
                    case .accounts:
                        AccountsView(state: state)
                    case .settings:
                        SettingsView(state: state)
                    }

                    if state.isLoading {
                        ZStack {
                            Color.black.opacity(0.18)
                                .ignoresSafeArea()

                            HStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text(state.loadingMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color(white: 0.12).opacity(0.92))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.3), radius: 16, x: 0, y: 6)
                            )
                            .environment(\.colorScheme, .dark)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let toast = state.toast {
                ToastOverlay(toast: toast)
                    .zIndex(100)
            }
        }
        .sheet(item: $state.switchTarget) { target in
            SwitchSheetView(target: target, state: state)
        }
        .alert("确认删除账号？", isPresented: Binding(
            get: { state.deleteTarget != nil },
            set: { if !$0 { state.deleteTarget = nil } }
        )) {
            Button("删除", role: .destructive) {
                state.confirmDelete()
            }
            Button("取消", role: .cancel) {
                state.deleteTarget = nil
            }
        } message: {
            if let target = state.deleteTarget {
                Text("确定要从本地账号列表中删除 \(target.email) 吗？此操作无法撤销。")
            }
        }
    }
}
