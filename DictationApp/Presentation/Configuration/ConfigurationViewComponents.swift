import SwiftUI

struct ConfigurationPage<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    private let content: Content

    init(
        title: String,
        detail: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ConfigurationAppearance.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ConfigurationEmblem(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }
}

struct ConfigurationEmblem: View {
    let systemImage: String
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(ConfigurationAppearance.emblem)
            .frame(width: size, height: size)
            .background(ConfigurationAppearance.highlight, in: .rect(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
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
                .labelStyle(ConfigurationSectionLabelStyle())
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ConfigurationSectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .foregroundStyle(ConfigurationAppearance.emblem)
                .accessibilityHidden(true)
            configuration.title
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
        let leadingInset = dynamicTypeSize.isAccessibilitySize
            ? 0
            : ConfigurationFormMetrics.labelWidth + ConfigurationFormMetrics.columnSpacing

        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leadingInset)
    }
}

extension View {
    func configurationPanel() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ConfigurationAppearance.surface, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(ConfigurationAppearance.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

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
            ConfigurationAppearance.success
        case .attention:
            ConfigurationAppearance.attention
        case .error:
            ConfigurationAppearance.error
        case .pending:
            .accentColor
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
    var forCommand = false

    @ViewBuilder
    var body: some View {
        if
            let descriptor = viewModel.descriptor(for: provider),
            let metadata = descriptor.capabilities[capability]
        {
            let isCloud = metadata.processingLocation == .cloud
            let commandDescription = isCloud
                ? "Command Mode sends your selected text and transcribed instruction to \(descriptor.displayName)."
                : "Command Mode processes your selected text and transcribed instruction on this Mac."
            let disclosure = Label(
                forCommand ? commandDescription : metadata.dataFlowDescription,
                systemImage:
                    isCloud
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
