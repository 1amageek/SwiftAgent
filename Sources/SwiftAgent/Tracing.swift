//
//  Tracing.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/17.
//

import Foundation
import Tracing
import Instrumentation

// MARK: - TracingStep

/// A step wrapper that adds distributed tracing to any step
public struct TracingStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output
    
    private let step: S
    private let spanName: String
    private let spanKind: SpanKind
    private let recordInputOutput: Bool
    
    /// Creates a new tracing step wrapper
    /// - Parameters:
    ///   - step: The step to wrap with tracing
    ///   - spanName: The name for the span (defaults to step type name)
    ///   - spanKind: The kind of span (internal, client, server, etc.)
    ///   - recordInputOutput: Whether to record input/output details
    public init(
        _ step: S,
        spanName: String? = nil,
        spanKind: SpanKind = .internal,
        recordInputOutput: Bool = false
    ) {
        self.step = step
        self.spanName = spanName ?? String(describing: type(of: step))
        self.spanKind = spanKind
        self.recordInputOutput = recordInputOutput
    }
    
    public func run(_ input: Input) async throws -> Output {
        try await withSpan(spanName, ofKind: spanKind) { span in
            // Set basic attributes
            span.attributes[SwiftAgentSpanAttributes.stepType] = String(describing: type(of: step))
            
            // Record input if requested
            if recordInputOutput {
                span.addEvent("input_received")
            }
            
            do {
                // Execute the wrapped step
                let output = try await step.run(input)
                
                // Record output if requested
                if recordInputOutput {
                    span.addEvent("output_generated")
                }
                
                // Mark span as successful
                // Span is successful by default, no need to set status
                return output
            } catch {
                // Record error
                span.recordError(error)
                throw error
            }
        }
    }
}

// MARK: - Step Extensions

public extension Step {
    /// Adds distributed tracing to this step
    /// - Parameters:
    ///   - name: The name for the span (defaults to step type name)
    ///   - kind: The kind of span (internal, client, server, etc.)
    ///   - recordInputOutput: Whether to record input/output details
    /// - Returns: A new step with tracing applied
    func trace(
        _ name: String? = nil,
        kind: SpanKind = .internal,
        recordInputOutput: Bool = false
    ) -> TracingStep<Self> {
        TracingStep(
            self,
            spanName: name,
            spanKind: kind,
            recordInputOutput: recordInputOutput
        )
    }
}