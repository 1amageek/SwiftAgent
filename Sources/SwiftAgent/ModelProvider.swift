//
//  ModelProvider.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

// MARK: - Model Provider (USE_OTHER_MODELS only)

#if USE_OTHER_MODELS

/// A protocol for providing language models.
///
/// `ModelProvider` abstracts the creation and configuration of language models,
/// allowing for different backends (MLX, OpenAI, etc.) to be used interchangeably.
///
/// - Note: This is only available when using OpenFoundationModels.
///   Apple's FoundationModels uses SystemLanguageModel directly.
///
/// ## Usage
///
/// ```swift
/// // Use a pre-configured model
/// let provider = PreloadedModelProvider(model: myModel)
///
/// // Use a lazy-loading provider
/// let provider = LazyModelProvider {
///     try await loadFunctionGemmaModel()
/// }
/// ```
public protocol ModelProvider: Sendable {

    /// Provides a language model instance.
    ///
    /// This method may load the model lazily or return a pre-loaded instance.
    ///
    /// - Returns: A language model instance.
    /// - Throws: `AgentError.modelLoadFailed` if the model cannot be loaded.
    func provideModel() async throws -> any LanguageModel

    /// The identifier of the model.
    var modelID: String { get }

    /// Whether the model is currently available.
    var isAvailable: Bool { get async }
}

// MARK: - Default Implementations

extension ModelProvider {

    public var isAvailable: Bool {
        get async {
            do {
                let model = try await provideModel()
                return model.isAvailable
            } catch {
                return false
            }
        }
    }
}

// MARK: - Preloaded Model Provider

/// A model provider that wraps an already-loaded model.
///
/// Use this when you have already loaded a model and want to provide it to an agent.
///
/// ```swift
/// let model = try await loadMyModel()
/// let provider = PreloadedModelProvider(model: model, id: "my-model")
/// ```
public struct PreloadedModelProvider: ModelProvider {

    private let model: any LanguageModel
    public let modelID: String

    /// Creates a provider with a pre-loaded model.
    ///
    /// - Parameters:
    ///   - model: The pre-loaded language model.
    ///   - id: An identifier for the model.
    public init(model: any LanguageModel, id: String = "preloaded") {
        self.model = model
        self.modelID = id
    }

    public func provideModel() async throws -> any LanguageModel {
        return model
    }

    public var isAvailable: Bool {
        get async {
            model.isAvailable
        }
    }
}

// MARK: - Lazy Model Provider

/// A model provider that loads the model on first use.
///
/// Use this for deferred model loading to improve startup time.
///
/// ```swift
/// let provider = LazyModelProvider(id: "function-gemma") {
///     let loader = ModelLoader()
///     let container = try await loader.loadModel("mlx-community/functiongemma-270m-it-bf16")
///     return MLXLanguageModel(modelContainer: container, card: FunctionGemmaModelCard())
/// }
/// ```
public actor LazyModelProvider: ModelProvider {

    public nonisolated let modelID: String
    private let loader: @Sendable () async throws -> any LanguageModel
    private var cachedModel: (any LanguageModel)?
    private var isLoading: Bool = false
    private var loadError: Error?

    /// Creates a lazy-loading model provider.
    ///
    /// - Parameters:
    ///   - id: An identifier for the model.
    ///   - loader: A closure that loads the model when called.
    public init(
        id: String,
        loader: @escaping @Sendable () async throws -> any LanguageModel
    ) {
        self.modelID = id
        self.loader = loader
    }

    public func provideModel() async throws -> any LanguageModel {
        // Return cached model if available
        if let model = cachedModel {
            return model
        }

        // Return previous error if loading failed
        if let error = loadError {
            throw AgentError.modelLoadFailed(underlyingError: error)
        }

        // Load the model
        isLoading = true
        defer { isLoading = false }

        do {
            let model = try await loader()
            cachedModel = model
            return model
        } catch {
            loadError = error
            throw AgentError.modelLoadFailed(underlyingError: error)
        }
    }

    public var isAvailable: Bool {
        get async {
            if let model = cachedModel {
                return model.isAvailable
            }
            return false
        }
    }

    /// Preloads the model if not already loaded.
    public func preload() async throws {
        _ = try await provideModel()
    }

    /// Clears the cached model.
    public func clearCache() {
        cachedModel = nil
        loadError = nil
    }
}

// MARK: - Model Provider Factory

/// Factory for creating common model providers.
///
/// This provides convenient methods for creating providers for common model types.
public enum ModelProviderFactory {

    /// Creates a provider for a pre-loaded model.
    public static func preloaded(
        _ model: any LanguageModel,
        id: String = "preloaded"
    ) -> PreloadedModelProvider {
        PreloadedModelProvider(model: model, id: id)
    }

    /// Creates a lazy-loading provider.
    public static func lazy(
        id: String,
        loader: @escaping @Sendable () async throws -> any LanguageModel
    ) -> LazyModelProvider {
        LazyModelProvider(id: id, loader: loader)
    }
}

#endif

// MARK: - Model Configuration

/// Configuration options for model behavior.
public struct ModelConfiguration: Sendable, Equatable {

    /// Maximum number of tokens to generate.
    public var maxTokens: Int?

    /// Temperature for generation (0.0 - 1.0).
    public var temperature: Double?

    /// Top-p sampling parameter.
    public var topP: Double?

    /// Stop sequences.
    public var stopSequences: [String]

    /// Timeout for generation.
    public var timeout: Duration?

    /// Creates a model configuration.
    public init(
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stopSequences: [String] = [],
        timeout: Duration? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.timeout = timeout
    }

    /// Default configuration.
    public static let `default` = ModelConfiguration()

    /// Configuration optimized for code generation.
    public static let code = ModelConfiguration(
        temperature: 0.2,
        topP: 0.95
    )

    /// Configuration optimized for creative tasks.
    public static let creative = ModelConfiguration(
        temperature: 0.8,
        topP: 0.9
    )

    /// Configuration for deterministic output.
    public static let deterministic = ModelConfiguration(
        temperature: 0.0
    )
}

// MARK: - Conversion to GenerationOptions

extension ModelConfiguration {

    /// Converts to OpenFoundationModels GenerationOptions.
    public func toGenerationOptions() -> GenerationOptions {
        var options = GenerationOptions()

        if let temp = temperature {
            options.temperature = temp
        }

        if let maxTok = maxTokens {
            options.maximumResponseTokens = maxTok
        }

        // Convert topP to SamplingMode
        if let topPValue = topP {
            options.sampling = .random(probabilityThreshold: topPValue)
        }

        return options
    }
}
