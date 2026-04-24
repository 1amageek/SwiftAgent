//
//  MetricsEmittingMiddleware.swift
//  SwiftAgent
//

import Foundation
import Metrics

/// Emits low-cardinality aggregate metrics for tool execution.
///
/// This middleware is intentionally separate from ``EventEmittingMiddleware``:
/// `RunEvent` remains the per-run truth for replay, UI, and debugging, while
/// metrics provide backend-agnostic counters/timers for operational dashboards.
///
/// SwiftAgent does not bootstrap a metrics backend. Applications that want
/// metrics should call `MetricsSystem.bootstrap(...)` at process startup, or
/// pass an explicit `MetricsFactory` to this middleware.
public struct MetricsEmittingMiddleware: ToolMiddleware {
    private let started: Counter
    private let completed: Counter
    private let failed: Counter
    private let active: Meter
    private let duration: Metrics.Timer

    public init(factory: MetricsFactory = MetricsSystem.factory) {
        self.started = Counter(
            label: SwiftAgentMetrics.toolExecutionsStarted,
            factory: factory
        )
        self.completed = Counter(
            label: SwiftAgentMetrics.toolExecutionsCompleted,
            factory: factory
        )
        self.failed = Counter(
            label: SwiftAgentMetrics.toolExecutionsFailed,
            factory: factory
        )
        self.active = Meter(
            label: SwiftAgentMetrics.toolExecutionsActive,
            factory: factory
        )
        self.duration = Metrics.Timer(
            label: SwiftAgentMetrics.toolExecutionDuration,
            factory: factory
        )
    }

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        started.increment()
        active.increment()

        let startedAt = ContinuousClock.now
        defer {
            active.decrement()
        }

        do {
            let result = try await next(context)
            recordFinished(startedAt: startedAt, success: result.success)
            return result
        } catch {
            recordFinished(startedAt: startedAt, success: false)
            throw error
        }
    }

    private func recordFinished(
        startedAt: ContinuousClock.Instant,
        success: Bool
    ) {
        let elapsed = startedAt.duration(to: ContinuousClock.now)
        duration.record(duration: elapsed)

        if success {
            completed.increment()
        } else {
            failed.increment()
        }
    }
}
