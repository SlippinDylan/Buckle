import SwiftUI

struct FinderExtensionStatusView: View {
    let controller: FinderExtensionController
    @State private var confirmingRestore = false

    var body: some View {
        switch controller.state {
        case .enabled:
            EmptyView()
        case .checking:
            ProgressView(localized("finder.checking")).controlSize(.small)
        case .missing:
            notice(localized("finder.missing"), detail: localized("finder.install.help")) {
                Button(localized("finder.show.app")) { controller.showApplication() }
            }
        case .unregistered:
            notice(localized("finder.unregistered"), detail: localized("finder.register.help")) {
                Button(localized("finder.register")) { Task { await controller.register() } }
            }
        case .disabled:
            notice(localized("finder.disabled"), detail: localized("finder.enable.help")) {
                Button(localized("finder.settings")) { controller.openSettings() }
                Button(localized("finder.enable")) { Task { await controller.enable() } }
            }
        case .invalidConfiguration(let message):
            notice(localized("finder.configuration.invalid"), detail: message) {
                Button(localized("finder.configuration.restore")) { confirmingRestore = true }
            }
            .alert(localized("finder.configuration.restore"), isPresented: $confirmingRestore) {
                Button(localized("finder.configuration.restore")) { Task { await controller.restoreConfiguration() } }
                Button(localized("cancel"), role: .cancel) {}
            } message: {
                Text(localized("finder.configuration.restore.help"))
            }
        case .failed(let message):
            notice(localized("finder.operation.failed"), detail: message) {
                Button(localized("finder.retry")) { Task { await controller.refresh() } }
                Button(localized("finder.settings")) { controller.openSettings() }
            }
        }
    }

    private func notice<Actions: View>(
        _ title: String, detail: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label(title, systemImage: "info.circle").font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack { actions() }.disabled(controller.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
