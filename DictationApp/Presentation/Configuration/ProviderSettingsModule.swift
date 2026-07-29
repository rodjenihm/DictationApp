import Combine
import SwiftUI

enum ProviderCredentialIntent: Equatable {
    case unchanged
    case replace
    case remove
}

struct ProviderCommitToken {
    let value: Any
}

struct ProviderSettingsValidationFailure: LocalizedError {
    let provider: ProviderID
    let capability: ProviderCapability?
    let kind: ProviderConfigurationIssueKind
    let message: String

    var errorDescription: String? { message }
}

@MainActor
protocol ProviderSettingsModule: AnyObject, ObservableObject {
    associatedtype DetailView: View

    var descriptor: ProviderDescriptor { get }
    var readiness: ProviderReadiness { get }
    var savedReadiness: ProviderReadiness { get }
    var isDirty: Bool { get }
    var hasProvisionalConfiguration: Bool { get }

    func reload()
    func discard()
    func validate(
        configuration: AppConfiguration,
        stages: Set<ProviderCapability>
    ) async throws
    func commit() throws -> ProviderCommitToken?
    func rollback(_ token: ProviderCommitToken)
    func didSave()
    func makeDetailView() -> DetailView
}

@MainActor
final class AnyProviderSettingsModule: ObservableObject, Identifiable {
    let descriptor: ProviderDescriptor

    var id: ProviderID { descriptor.id }
    var readiness: ProviderReadiness { readinessClosure() }
    var savedReadiness: ProviderReadiness {
        savedReadinessClosure()
    }
    var isDirty: Bool { isDirtyClosure() }
    var hasProvisionalConfiguration: Bool { provisionalClosure() }

    private let readinessClosure: () -> ProviderReadiness
    private let savedReadinessClosure: () -> ProviderReadiness
    private let isDirtyClosure: () -> Bool
    private let provisionalClosure: () -> Bool
    private let reloadClosure: () -> Void
    private let discardClosure: () -> Void
    private let validateClosure:
        (AppConfiguration, Set<ProviderCapability>) async throws -> Void
    private let commitClosure: () throws -> ProviderCommitToken?
    private let rollbackClosure: (ProviderCommitToken) -> Void
    private let didSaveClosure: () -> Void
    private let detailViewClosure: () -> AnyView
    private var cancellable: AnyCancellable?

    init<Module: ProviderSettingsModule>(_ module: Module) {
        descriptor = module.descriptor
        readinessClosure = { module.readiness }
        savedReadinessClosure = { module.savedReadiness }
        isDirtyClosure = { module.isDirty }
        provisionalClosure = { module.hasProvisionalConfiguration }
        reloadClosure = { module.reload() }
        discardClosure = { module.discard() }
        validateClosure = { configuration, stages in
            try await module.validate(
                configuration: configuration,
                stages: stages
            )
        }
        commitClosure = { try module.commit() }
        rollbackClosure = { module.rollback($0) }
        didSaveClosure = { module.didSave() }
        detailViewClosure = { AnyView(module.makeDetailView()) }
        cancellable = module.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func reload() {
        reloadClosure()
    }

    func discard() {
        discardClosure()
    }

    func validate(
        configuration: AppConfiguration,
        stages: Set<ProviderCapability>
    ) async throws {
        try await validateClosure(configuration, stages)
    }

    func commit() throws -> ProviderCommitToken? {
        try commitClosure()
    }

    func rollback(_ token: ProviderCommitToken) {
        rollbackClosure(token)
    }

    func didSave() {
        didSaveClosure()
    }

    func makeDetailView() -> AnyView {
        detailViewClosure()
    }
}
