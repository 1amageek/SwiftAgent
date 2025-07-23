//
//  Tracing.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/17.
//

import Foundation

// MARK: - Tracer Protocol

/// A protocol that defines tracing capabilities for agent workflows
///
/// Tracers provide visibility into agent execution, allowing you to view, debug, and optimize workflows.
public protocol AgentTracer: Sendable {
    /// Starts a new trace for an operation
    /// - Parameter operation: The name of the operation being traced
    /// - Returns: A trace context for the started operation
    func startTrace<T: Sendable>(_ operation: String) async -> TraceContext<T>
    
    /// Ends a trace with the result
    /// - Parameters:
    ///   - context: The trace context to end
    ///   - result: The result of the operation (success or failure)
    func endTrace<T: Sendable>(_ context: TraceContext<T>, result: Result<T, Error>) async
    
    /// Records a custom event during tracing
    /// - Parameters:
    ///   - context: The trace context
    ///   - event: The event name
    ///   - metadata: Additional metadata for the event
    func recordEvent<T: Sendable>(_ context: TraceContext<T>, event: String, metadata: [String: String]) async
}

// MARK: - Trace Context

/// Context information for a trace operation
public struct TraceContext<T>: Sendable {
    /// Unique identifier for this trace
    public let id: UUID
    
    /// The name of the operation being traced
    public let operation: String
    
    /// When the trace started
    public let startTime: Date
    
    /// Parent trace ID if this is a nested trace
    public let parentId: UUID?
    
    /// Additional metadata for the trace  
    public var metadata: [String: String]
    
    /// Creates a new trace context
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - operation: Operation name
    ///   - startTime: Start time
    ///   - parentId: Parent trace ID
    ///   - metadata: Additional metadata
    public init(
        id: UUID = UUID(),
        operation: String,
        startTime: Date = Date(),
        parentId: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.operation = operation
        self.startTime = startTime
        self.parentId = parentId
        self.metadata = metadata
    }
}

// MARK: - Trace Event

/// Represents an event that occurred during tracing
public struct TraceEvent: Sendable {
    public let timestamp: Date
    public let event: String
    public let metadata: [String: String]
    
    public init(event: String, metadata: [String: String] = [:]) {
        self.timestamp = Date()
        self.event = event
        self.metadata = metadata
    }
}

// MARK: - Tracing Step Wrapper

/// A step wrapper that adds tracing to any step
public struct TracingStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output
    
    private let step: S
    private let tracer: AgentTracer
    private let operationName: String
    
    /// Creates a new tracing step wrapper
    /// - Parameters:
    ///   - step: The step to wrap with tracing
    ///   - tracer: The tracer to use
    ///   - operationName: The name for the traced operation
    public init(step: S, tracer: AgentTracer, operationName: String? = nil) {
        self.step = step
        self.tracer = tracer
        self.operationName = operationName ?? String(describing: type(of: step))
    }
    
    public func run(_ input: Input) async throws -> Output {
        let context: TraceContext<Output> = await tracer.startTrace(operationName)
        
        // Record input information
        await tracer.recordEvent(context, event: "input_received", metadata: [
            "input_type": String(describing: type(of: input))
        ])
        
        do {
            let result = try await step.run(input)
            
            // Record successful completion
            await tracer.recordEvent(context, event: "execution_completed", metadata: [
                "output_type": String(describing: type(of: result))
            ])
            
            await tracer.endTrace(context, result: .success(result))
            return result
        } catch {
            // Record error
            await tracer.recordEvent(context, event: "execution_failed", metadata: [
                "error_type": String(describing: type(of: error)),
                "error_description": error.localizedDescription
            ])
            
            await tracer.endTrace(context, result: .failure(error))
            throw error
        }
    }
}

// MARK: - Console Tracer

/// A simple tracer that outputs to the console
public struct ConsoleTracer: AgentTracer {
    private let includeMetadata: Bool
    private let dateFormatter: DateFormatter
    
    /// Creates a console tracer
    /// - Parameter includeMetadata: Whether to include metadata in console output
    public init(includeMetadata: Bool = true) {
        self.includeMetadata = includeMetadata
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    public func startTrace<T: Sendable>(_ operation: String) async -> TraceContext<T> {
        let context = TraceContext<T>(operation: operation)
        let timestamp = dateFormatter.string(from: context.startTime)
        print("[TRACE] [\(timestamp)] Started: \(operation) (\(context.id.uuidString.prefix(8)))")
        return context
    }
    
    public func endTrace<T: Sendable>(_ context: TraceContext<T>, result: Result<T, Error>) async {
        let duration = Date().timeIntervalSince(context.startTime)
        let timestamp = dateFormatter.string(from: Date())
        let durationString = String(format: "%.3fs", duration)
        
        switch result {
        case .success:
            print("[TRACE] [\(timestamp)] ✅ Completed: \(context.operation) (\(context.id.uuidString.prefix(8))) in \(durationString)")
        case .failure(let error):
            print("[TRACE] [\(timestamp)] ❌ Failed: \(context.operation) (\(context.id.uuidString.prefix(8))) - \(error.localizedDescription)")
        }
        
        if includeMetadata && !context.metadata.isEmpty {
            print("[TRACE] [\(timestamp)]    Metadata: \(context.metadata)")
        }
    }
    
    public func recordEvent<T: Sendable>(_ context: TraceContext<T>, event: String, metadata: [String: String]) async {
        let timestamp = dateFormatter.string(from: Date())
        print("[TRACE] [\(timestamp)] 📝 Event: \(event) (\(context.id.uuidString.prefix(8)))")
        
        if includeMetadata && !metadata.isEmpty {
            print("[TRACE] [\(timestamp)]    Event metadata: \(metadata)")
        }
    }
}

// MARK: - Memory Tracer

/// A tracer that stores traces in memory for later analysis
public actor MemoryTracer: AgentTracer {
    private var traces: [UUID: TraceRecord] = [:]
    private var activeTraces: [UUID: TraceContext<Any>] = [:]
    
    /// Retrieves all completed traces
    public func getAllTraces() -> [TraceRecord] {
        Array(traces.values).sorted { $0.startTime < $1.startTime }
    }
    
    /// Retrieves a specific trace by ID
    /// - Parameter id: The trace ID
    /// - Returns: The trace record if found
    public func getTrace(id: UUID) -> TraceRecord? {
        traces[id]
    }
    
    /// Clears all stored traces
    public func clearTraces() {
        traces.removeAll()
        activeTraces.removeAll()
    }
    
    public func startTrace<T: Sendable>(_ operation: String) async -> TraceContext<T> {
        let context = TraceContext<T>(operation: operation)
        activeTraces[context.id] = TraceContext<Any>(
            id: context.id,
            operation: context.operation,
            startTime: context.startTime,
            parentId: context.parentId,
            metadata: context.metadata
        )
        return context
    }
    
    public func endTrace<T: Sendable>(_ context: TraceContext<T>, result: Result<T, Error>) async {
        let endTime = Date()
        let duration = endTime.timeIntervalSince(context.startTime)
        
        let record = TraceRecord(
            id: context.id,
            operation: context.operation,
            startTime: context.startTime,
            endTime: endTime,
            duration: duration,
            parentId: context.parentId,
            success: result.isSuccess,
            error: result.error?.localizedDescription,
            metadata: context.metadata,
            events: [] // Events would be collected if we tracked them
        )
        
        traces[context.id] = record
        activeTraces.removeValue(forKey: context.id)
    }
    
    public func recordEvent<T: Sendable>(_ context: TraceContext<T>, event: String, metadata: [String: String]) async {
        // For simplicity, we're not storing events in this implementation
        // but they could be added to the TraceRecord structure
    }
}

// MARK: - Trace Record

/// A completed trace record
public struct TraceRecord: Sendable {
    public let id: UUID
    public let operation: String
    public let startTime: Date
    public let endTime: Date
    public let duration: TimeInterval
    public let parentId: UUID?
    public let success: Bool
    public let error: String?
    public let metadata: [String: String]
    public let events: [TraceEvent]
    
    public init(
        id: UUID,
        operation: String,
        startTime: Date,
        endTime: Date,
        duration: TimeInterval,
        parentId: UUID?,
        success: Bool,
        error: String?,
        metadata: [String: String],
        events: [TraceEvent]
    ) {
        self.id = id
        self.operation = operation
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.parentId = parentId
        self.success = success
        self.error = error
        self.metadata = metadata
        self.events = events
    }
}

// MARK: - Result Extensions

extension Result {
    /// Whether this result represents a success
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
    
    /// The error if this result is a failure
    var error: Failure? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}

// MARK: - Step Extensions

public extension Step {
    /// Adds tracing to this step
    /// - Parameters:
    ///   - tracer: The tracer to use
    ///   - operationName: Custom operation name (defaults to type name)
    /// - Returns: A new step with tracing applied
    func withTracing(
        tracer: AgentTracer,
        operationName: String? = nil
    ) -> TracingStep<Self> {
        TracingStep(step: self, tracer: tracer, operationName: operationName)
    }
}