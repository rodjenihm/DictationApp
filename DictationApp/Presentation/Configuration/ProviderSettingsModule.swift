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
    var provisionalTranscriptionLanguage: LanguageSelection? { get }
    var hasResolvedFirstRunEligibility: Bool { get }
    var isEligibleForFirstRunDefault: Bool { get }

    func reload()
    func discard()
    func refreshSystemState()
    func stageTranscriptionLanguage(_ language: LanguageSelection)
    func validate(
        configuration: AppConfiguration,
        stages: Set<ProviderCapability>
    ) async throws
    func commit() throws -> ProviderCommitToken?
    func rollback(_ token: ProviderCommitToken)
    func didSave()
    func makeDetailView() -> DetailView
}

extension ProviderSettingsModule {
    var provisionalTranscriptionLanguage: LanguageSelection? {
        nil
    }

    var hasResolvedFirstRunEligibility: Bool {
        true
    }

    var isEligibleForFirstRunDefault: Bool {
        false
    }

    func refreshSystemState() {}

    func stageTranscriptionLanguage(_ language: LanguageSelection) {}
}

@MainActor
final class AnyProviderSettingsModule: ObservableObject, Identifiable {
    var descriptor: ProviderDescriptor { descriptorClosure() }

    var id: ProviderID { descriptor.id }
    var readiness: ProviderReadiness { readinessClosure() }
    var savedReadiness: ProviderReadiness {
        savedReadinessClosure()
    }
    var isDirty: Bool { isDirtyClosure() }
    var hasProvisionalConfiguration: Bool { provisionalClosure() }
    var provisionalTranscriptionLanguage: LanguageSelection? {
        provisionalTranscriptionLanguageClosure()
    }
    var hasResolvedFirstRunEligibility: Bool {
        hasResolvedFirstRunEligibilityClosure()
    }
    var isEligibleForFirstRunDefault: Bool {
        isEligibleForFirstRunDefaultClosure()
    }

    private let descriptorClosure: () -> ProviderDescriptor
    private let readinessClosure: () -> ProviderReadiness
    private let savedReadinessClosure: () -> ProviderReadiness
    private let isDirtyClosure: () -> Bool
    private let provisionalClosure: () -> Bool
    private let provisionalTranscriptionLanguageClosure:
        () -> LanguageSelection?
    private let hasResolvedFirstRunEligibilityClosure: () -> Bool
    private let isEligibleForFirstRunDefaultClosure: () -> Bool
    private let reloadClosure: () -> Void
    private let discardClosure: () -> Void
    private let refreshSystemStateClosure: () -> Void
    private let stageTranscriptionLanguageClosure:
        (LanguageSelection) -> Void
    private let validateClosure:
        (AppConfiguration, Set<ProviderCapability>) async throws -> Void
    private let commitClosure: () throws -> ProviderCommitToken?
    private let rollbackClosure: (ProviderCommitToken) -> Void
    private let didSaveClosure: () -> Void
    private let detailViewClosure: () -> AnyView
    private var cancellable: AnyCancellable?

    init<Module: ProviderSettingsModule>(_ module: Module) {
        descriptorClosure = { module.descriptor }
        readinessClosure = { module.readiness }
        savedReadinessClosure = { module.savedReadiness }
        isDirtyClosure = { module.isDirty }
        provisionalClosure = { module.hasProvisionalConfiguration }
        provisionalTranscriptionLanguageClosure = {
            module.provisionalTranscriptionLanguage
        }
        hasResolvedFirstRunEligibilityClosure = {
            module.hasResolvedFirstRunEligibility
        }
        isEligibleForFirstRunDefaultClosure = {
            module.isEligibleForFirstRunDefault
        }
        reloadClosure = { module.reload() }
        discardClosure = { module.discard() }
        refreshSystemStateClosure = {
            module.refreshSystemState()
        }
        stageTranscriptionLanguageClosure = {
            module.stageTranscriptionLanguage($0)
        }
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

    func refreshSystemState() {
        refreshSystemStateClosure()
    }

    func stageTranscriptionLanguage(_ language: LanguageSelection) {
        stageTranscriptionLanguageClosure(language)
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
