import SwiftUI

struct ConfigurationPage<Content: View>: View {
    let title: String
    let detail: String
    private let content: Content

    init(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
    }
}

struct ConfigurationSettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

struct ConfigurationIssueLabel: View {
    let message: String
    var warning = false

    var body: some View {
        Label(
            message,
            systemImage:
                warning
                ? "exclamationmark.triangle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(warning ? Color.orange : Color.red)
    }
}

struct ConfigurationPermissionStatusLabel: View {
    let title: String
    let granted: Bool

    var body: some View {
        Label(
            title,
            systemImage:
                granted
                ? "checkmark.circle.fill"
                : "exclamationmark.circle"
        )
        .foregroundStyle(granted ? Color.green : Color.secondary)
    }
}

struct ConfigurationModelLabel: View {
    let model: ProviderModelDescriptor

    var body: some View {
        HStack {
            Text(model.displayName)
            if let detail = model.detail {
                Text("— \(detail)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ConfigurationProviderPickerLabel: View {
    let descriptor: ProviderDescriptor
    let capability: ProviderCapability

    var body: some View {
        HStack {
            Text(descriptor.displayName)
            if let metadata = descriptor.capabilities[capability] {
                Text("— \(metadata.processingLocation.displayName)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ConfigurationStageDisclosure: View {
    let viewModel: ConfigurationViewModel
    let provider: ProviderID
    let capability: ProviderCapability
    var compact = true

    @ViewBuilder
    var body: some View {
        if
            let descriptor = viewModel.descriptor(for: provider),
            let metadata = descriptor.capabilities[capability]
        {
            let disclosure = Label(
                metadata.dataFlowDescription,
                systemImage:
                    metadata.processingLocation == .cloud
                    ? "icloud.and.arrow.up"
                    : "desktopcomputer"
            )
            if compact {
                disclosure
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                disclosure
            }
        }
    }
}

struct ConfigurationNoProviderView: View {
    @Bindable var viewModel: ConfigurationViewModel
    let capability: ProviderCapability

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "No provider configured",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
            Text(
                "Configure a provider that supports \(capability.displayName.lowercased())."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("Configure Providers") {
                viewModel.selectedDestination = .providers
            }
        }
    }
}
