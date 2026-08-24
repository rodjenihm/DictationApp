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
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
    }
}

struct ConfigurationSection<Content: View>: View {
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
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ConfigurationForm<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ConfigurationFormMetrics {
    static let labelWidth: CGFloat = 128
    static let columnSpacing: CGFloat = 14
    static let fieldWidth: CGFloat = 220
}

struct ConfigurationSettingRow<Content: View, Detail: View>: View {
    let title: String
    private let content: Content
    private let detail: Detail
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.title = title
        self.content = content()
        self.detail = detail()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    valueColumn
                }
            } else {
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: ConfigurationFormMetrics.columnSpacing
                ) {
                    label
                        .frame(
                            width: ConfigurationFormMetrics.labelWidth,
                            alignment: .leading
                        )
                    valueColumn
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var label: some View {
        Text(title)
    }

    private var valueColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ConfigurationSettingRow where Detail == EmptyView {
    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, content: content) {
            EmptyView()
        }
    }
}

struct ConfigurationFormSupplementary<Content: View>: View {
    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(
                alignment: .firstTextBaseline,
                spacing: ConfigurationFormMetrics.columnSpacing
            ) {
                Color.clear
                    .frame(width: ConfigurationFormMetrics.labelWidth)
                    .accessibilityHidden(true)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension View {
    func configurationFieldControl() -> some View {
        frame(
            width: ConfigurationFormMetrics.fieldWidth,
            alignment: .leading
        )
        .controlSize(.regular)
    }

    @ViewBuilder
    func configurationPickerControl() -> some View {
        if #available(macOS 26.0, *) {
            buttonSizing(.flexible)
                .configurationFieldControl()
        } else {
            configurationFieldControl()
        }
    }
}

enum ConfigurationStatusStyle {
    case neutral
    case success
    case attention
    case error
    case pending

    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .success:
            .green
        case .attention:
            .orange
        case .error:
            .red
        case .pending:
            .blue
        }
    }
}

struct ConfigurationStatusLabel: View {
    let title: String
    let systemImage: String
    let style: ConfigurationStatusStyle
    var font: Font = .caption

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(font)
            .foregroundStyle(style.color)
    }
}

struct ConfigurationIssueLabel: View {
    let message: String
    var warning = false

    var body: some View {
        ConfigurationStatusLabel(
            title: message,
            systemImage: warning
                ? "exclamationmark.triangle.fill"
                : "exclamationmark.circle.fill",
            style: warning ? .attention : .error
        )
    }
}

struct ConfigurationPermissionStatusLabel: View {
    let title: String
    let granted: Bool

    var body: some View {
        ConfigurationStatusLabel(
            title: title,
            systemImage: granted
                ? "checkmark.circle.fill"
                : "exclamationmark.circle",
            style: granted ? .success : .neutral,
            font: .body
        )
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
            ConfigurationStatusLabel(
                title: "No provider configured",
                systemImage: "exclamationmark.triangle.fill",
                style: .attention,
                font: .body
            )
            Text(
                "Configure a provider that supports \(capability.displayName.lowercased())."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("Configure Providers") {
                viewModel.selectedDestination = .providers
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.06), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.orange.opacity(0.18), lineWidth: 0.5)
        }
    }
}
