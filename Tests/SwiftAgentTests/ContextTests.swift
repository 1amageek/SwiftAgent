import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Context Keys

/// A simple counter context for testing
enum CounterContext: ContextKey {
    @TaskLocal private static var _current: Int?

    public static var defaultValue: Int { 0 }

    public static var current: Int { _current ?? defaultValue }

    public static func withValue<T: Sendable>(
        _ value: Int,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

/// A configuration context for testing
struct TestConfig: Sendable {
    let name: String
    let maxRetries: Int

    static let empty = TestConfig(name: "", maxRetries: 0)
}

enum ConfigContext: ContextKey {
    @TaskLocal private static var _current: TestConfig?

    public static var defaultValue: TestConfig { .empty }

    public static var current: TestConfig { _current ?? defaultValue }

    public static func withValue<T: Sendable>(
        _ value: TestConfig,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

/// A tracker context for testing shared state
final class URLTracker: @unchecked Sendable {
    private var _visitedURLs: Set<URL> = []
    private let lock = NSLock()

    var visitedURLs: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return _visitedURLs
    }

    func markVisited(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        _visitedURLs.insert(url)
    }

    func hasVisited(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _visitedURLs.contains(url)
    }
}

enum TrackerContext: ContextKey {
    @TaskLocal private static var _current: URLTracker?

    public static var defaultValue: URLTracker { URLTracker() }

    public static var current: URLTracker { _current ?? defaultValue }

    public static func withValue<T: Sendable>(
        _ value: URLTracker,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

// MARK: - Context Tests

@Suite("Context Tests")
struct ContextTests {

    @Test("Context returns defaultValue by default")
    func contextDefaultValueByDefault() {
        #expect(CounterContext.current == 0)  // defaultValue
    }

    @Test("withContext sets value for operation")
    func withContextSetsValue() async throws {
        let result = await withContext(CounterContext.self, value: 42) {
            CounterContext.current
        }

        #expect(result == 42)
    }

    @Test("withContext restores defaultValue after operation")
    func withContextRestoresAfter() async throws {
        _ = await withContext(CounterContext.self, value: 100) {
            // Value is set here
            #expect(CounterContext.current == 100)
        }

        // Value should be defaultValue after
        #expect(CounterContext.current == 0)
    }

    @Test("withContext returns operation result")
    func withContextReturnsResult() async throws {
        let result = await withContext(CounterContext.self, value: 10) {
            CounterContext.current * 2
        }

        #expect(result == 20)
    }

    @Test("withContext propagates errors")
    func withContextPropagatesErrors() async throws {
        struct TestError: Error {}

        await #expect(throws: TestError.self) {
            try await withContext(CounterContext.self, value: 1) {
                throw TestError()
            }
        }
    }

    @Test("defaultValue is used when no context is set")
    func defaultValueIsUsed() async throws {
        // Without withContext, should use defaultValue
        #expect(CounterContext.current == 0)
        #expect(ConfigContext.current.name == "")
    }
}

// MARK: - @Context Property Wrapper Tests

@Suite("@Context Property Wrapper Tests")
struct ContextPropertyWrapperTests {

    struct CounterAccessingStep: Step {
        @Context(CounterContext.self) var counter: Int

        func run(_ input: Int) async throws -> Int {
            return counter + input
        }
    }

    @Test("@Context provides access to context value")
    func contextWrapperProvidesAccess() async throws {
        let step = CounterAccessingStep()

        let result = try await withContext(CounterContext.self, value: 100) {
            try await step.run(5)
        }

        #expect(result == 105)
    }

    @Test("Step.run with context parameter")
    func stepRunWithContextParameter() async throws {
        let step = CounterAccessingStep()

        let result = try await step.run(10, context: CounterContext.self, value: 50)

        #expect(result == 60)
    }
}

// MARK: - Nested Context Tests

@Suite("Nested Context Tests")
struct NestedContextTests {

    struct OuterStep: Step {
        @Context(CounterContext.self) var counter: Int

        func run(_ input: Int) async throws -> Int {
            let innerResult = try await InnerStep().run(input)
            return counter + innerResult
        }
    }

    struct InnerStep: Step {
        @Context(CounterContext.self) var counter: Int

        func run(_ input: Int) async throws -> Int {
            return counter * input
        }
    }

    @Test("Nested steps share same context")
    func nestedStepsShareContext() async throws {
        let step = OuterStep()

        let result = try await withContext(CounterContext.self, value: 10) {
            try await step.run(3)
        }

        // Inner: 10 * 3 = 30, Outer: 10 + 30 = 40
        #expect(result == 40)
    }

    @Test("Nested withContext overrides outer context")
    func nestedWithContextOverrides() async throws {
        let result = await withContext(CounterContext.self, value: 10) {
            let outer = CounterContext.current

            let inner = await withContext(CounterContext.self, value: 100) {
                CounterContext.current
            }

            // After inner block, should be back to outer value
            let afterInner = CounterContext.current

            return (outer, inner, afterInner)
        }

        #expect(result.0 == 10)
        #expect(result.1 == 100)
        #expect(result.2 == 10)
    }
}

// MARK: - Multiple Context Types Tests

@Suite("Multiple Context Types Tests")
struct MultipleContextTypesTests {

    struct MultiContextStep: Step {
        @Context(CounterContext.self) var counter: Int
        @Context(ConfigContext.self) var config: TestConfig

        func run(_ input: String) async throws -> String {
            return "\(config.name): \(input) (counter=\(counter), retries=\(config.maxRetries))"
        }
    }

    @Test("Step accesses multiple context types")
    func stepAccessesMultipleContexts() async throws {
        let step = MultiContextStep()
        let config = TestConfig(name: "TestRunner", maxRetries: 3)

        let result = try await withContext(CounterContext.self, value: 42) {
            try await withContext(ConfigContext.self, value: config) {
                try await step.run("hello")
            }
        }

        #expect(result == "TestRunner: hello (counter=42, retries=3)")
    }
}

// MARK: - Context with Reference Type Tests

@Suite("Context with Reference Type Tests")
struct ContextReferenceTypeTests {

    struct TrackerStep: Step {
        @Context(TrackerContext.self) var tracker: URLTracker

        func run(_ input: URL) async throws -> Bool {
            if tracker.hasVisited(input) {
                return false
            }
            tracker.markVisited(input)
            return true
        }
    }

    @Test("Context shares reference type across steps")
    func contextSharesReferenceType() async throws {
        let tracker = URLTracker()
        let step = TrackerStep()
        let url1 = URL(string: "https://example.com")!
        let url2 = URL(string: "https://test.com")!

        let results = try await withContext(TrackerContext.self, value: tracker) {
            let r1 = try await step.run(url1)
            let r2 = try await step.run(url2)
            let r3 = try await step.run(url1)  // Already visited
            return (r1, r2, r3)
        }

        #expect(results.0 == true)
        #expect(results.1 == true)
        #expect(results.2 == false)
        #expect(tracker.visitedURLs.count == 2)
    }

    @Test("Multiple steps share same tracker via context")
    func multipleStepsShareTracker() async throws {
        let tracker = URLTracker()
        let step1 = TrackerStep()
        let step2 = TrackerStep()

        try await withContext(TrackerContext.self, value: tracker) {
            _ = try await step1.run(URL(string: "https://a.com")!)
            _ = try await step2.run(URL(string: "https://b.com")!)
            _ = try await step1.run(URL(string: "https://c.com")!)
        }

        #expect(tracker.visitedURLs.count == 3)
    }
}

// MARK: - Context Concurrent Access Tests

@Suite("Context Concurrent Access Tests")
struct ContextConcurrentTests {

    @Test("Context is accessible in concurrent tasks")
    func contextInConcurrentTasks() async throws {
        let tracker = URLTracker()

        await withContext(TrackerContext.self, value: tracker) {
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<10 {
                    group.addTask {
                        let url = URL(string: "https://site\(i).com")!
                        tracker.markVisited(url)
                    }
                }
            }
        }

        #expect(tracker.visitedURLs.count == 10)
    }
}
