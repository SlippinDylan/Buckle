import SwiftUI

struct MouseResetView: View {
    let controller: MouseResetController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(localized("mouse.reset"), systemImage: "computermouse")
                .font(.headline)
            switch controller.state {
            case .idle:
                EmptyView()
            case .running(let current):
                Text(localized("mouse.progress.help"))
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(MouseResetStep.allCases, id: \.rawValue) { step in
                    HStack {
                        if step.rawValue < current.rawValue {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if step == current {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                        }
                        Text(localized(step.titleKey))
                    }
                }
            case .succeeded:
                Label(localized("mouse.success"), systemImage: "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(.green)
                Button(localized("done")) { controller.dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .failed(let step, let message):
                Label(localized("mouse.failed"), systemImage: "exclamationmark.circle.fill")
                    .font(.title3).foregroundStyle(.red)
                Text(localized(step.titleKey)).font(.callout)
                ScrollView { Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 160)
                Button(localized("done")) { controller.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
    }
}
