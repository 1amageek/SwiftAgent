//
//  MetricsEmittingMiddlewareTests.swift
//  SwiftAgent
//

import MetricsTestKit
import Testing
@testable import SwiftAgent

@Suite("MetricsEmittingMiddleware")
struct MetricsEmittingMiddlewareTests {
    enum FixtureError: Error {
        case failed
    }

    @Test("Records successful tool execution metrics")
    func recordsSuccessMetrics() async throws {
        let metrics = TestMetrics()
        let middleware = MetricsEmittingMiddleware(factory: metrics)
        let context = ToolContext(toolName: "Echo", arguments: #"{"value":"hello"}"#)

        let result = try await middleware.handle(context) { _ in
            .success("ok", duration: .zero)
        }

        #expect(result.output == "ok")
        #expect(try metrics.expectCounter(SwiftAgentMetrics.toolExecutionsStarted).totalValue == 1)
        #expect(try metrics.expectCounter(SwiftAgentMetrics.toolExecutionsCompleted).totalValue == 1)
        #expect(try metrics.expectMeter(SwiftAgentMetrics.toolExecutionsActive).lastValue == 0)
        #expect(try metrics.expectTimer(SwiftAgentMetrics.toolExecutionDuration).values.count == 1)
    }

    @Test("Records failed tool execution metrics")
    func recordsFailureMetrics() async throws {
        let metrics = TestMetrics()
        let middleware = MetricsEmittingMiddleware(factory: metrics)
        let context = ToolContext(toolName: "Echo", arguments: #"{"value":"hello"}"#)

        await #expect(throws: FixtureError.self) {
            _ = try await middleware.handle(context) { _ in
                throw FixtureError.failed
            }
        }

        #expect(try metrics.expectCounter(SwiftAgentMetrics.toolExecutionsStarted).totalValue == 1)
        #expect(try metrics.expectCounter(SwiftAgentMetrics.toolExecutionsFailed).totalValue == 1)
        #expect(try metrics.expectMeter(SwiftAgentMetrics.toolExecutionsActive).lastValue == 0)
        #expect(try metrics.expectTimer(SwiftAgentMetrics.toolExecutionDuration).values.count == 1)
    }

    @Test("ToolRuntimeConfiguration inserts metrics before permission middleware")
    func configurationInsertsMetricsBeforePermission() throws {
        let metrics = TestMetrics()
        let configuration = ToolRuntimeConfiguration.default.withMetrics(factory: metrics)

        let metricsIndex = try #require(configuration.middleware.firstIndex { $0 is MetricsEmittingMiddleware })
        let permissionIndex = try #require(configuration.middleware.firstIndex { $0 is PermissionMiddleware })

        #expect(metricsIndex < permissionIndex)
    }
}
