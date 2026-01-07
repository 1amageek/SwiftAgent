import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Contextable Types

/// A simple counter for testing
@Contextable
struct Counter: Contextable, Equatable {
    static var defaultValue: Counter { Counter(value: 0) }
    let value: Int
}

/// A configuration for testing
@Contextable
struct TestConfig: Contextable, Equatable {
    static var defaultValue: TestConfig { TestConfig(name: "", maxRetries: 0) }
    let name: String
    let maxRetries: Int
}

/// A tracker for testing shared state
@Contextable
final class URLTracker: Contextable, @unchecked Sendable {
    static var defaultValue: URLTracker { URLTracker() }

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

// MARK: - Context Tests

@Suite("Context Tests")
struct ContextTests {

    @Test("Context returns defaultValue by default")
    func contextDefaultValueByDefault() {
        #expect(CounterContext.current.value == 0)
    }

    @Test("withContext sets value for operation")
    func withContextSetsValue() async throws {
        let result = await withContext(CounterContext.self, value: Counter(value: 42)) {
            CounterContext.current
        }

        #expect(result.value == 42)
    }

    @Test("withContext restores defaultValue after operation")
    func withContextRestoresAfter() async throws {
        _ = await withContext(CounterContext.self, value: Counter(value: 100)) {
            #expect(CounterContext.current.value == 100)
        }

        #expect(CounterContext.current.value == 0)
    }

    @Test("withContext returns operation result")
    func withContextReturnsResult() async throws {
        let result = await withContext(CounterContext.self, value: Counter(value: 10)) {
            CounterContext.current.value * 2
        }

        #expect(result == 20)
    }

    @Test("withContext propagates errors")
    func withContextPropagatesErrors() async throws {
        struct TestError: Error {}

        await #expect(throws: TestError.self) {
            try await withContext(CounterContext.self, value: Counter(value: 1)) {
                throw TestError()
            }
        }
    }

    @Test("defaultValue is used when no context is set")
    func defaultValueIsUsed() async throws {
        #expect(CounterContext.current.value == 0)
        #expect(TestConfigContext.current.name == "")
    }
}

// MARK: - @Context Property Wrapper Tests

@Suite("@Context Property Wrapper Tests")
struct ContextPropertyWrapperTests {

    struct CounterAccessingStep: Step {
        @Context var counter: Counter

        func run(_ input: Int) async throws -> Int {
            return counter.value + input
        }
    }

    @Test("@Context provides access to context value")
    func contextWrapperProvidesAccess() async throws {
        let step = CounterAccessingStep()

        let result = try await step
            .context(Counter(value: 100))
            .run(5)

        #expect(result == 105)
    }

    @Test("Step.context() modifier")
    func stepContextModifier() async throws {
        let step = CounterAccessingStep()

        let result = try await step
            .context(Counter(value: 50))
            .run(10)

        #expect(result == 60)
    }
}

// MARK: - Nested Context Tests

@Suite("Nested Context Tests")
struct NestedContextTests {

    struct OuterStep: Step {
        @Context var counter: Counter

        func run(_ input: Int) async throws -> Int {
            let innerResult = try await InnerStep().run(input)
            return counter.value + innerResult
        }
    }

    struct InnerStep: Step {
        @Context var counter: Counter

        func run(_ input: Int) async throws -> Int {
            return counter.value * input
        }
    }

    @Test("Nested steps share same context")
    func nestedStepsShareContext() async throws {
        let step = OuterStep()

        let result = try await step
            .context(Counter(value: 10))
            .run(3)

        // Inner: 10 * 3 = 30, Outer: 10 + 30 = 40
        #expect(result == 40)
    }

    @Test("Nested withContext overrides outer context")
    func nestedWithContextOverrides() async throws {
        let result = await withContext(CounterContext.self, value: Counter(value: 10)) {
            let outer = CounterContext.current

            let inner = await withContext(CounterContext.self, value: Counter(value: 100)) {
                CounterContext.current
            }

            let afterInner = CounterContext.current

            return (outer.value, inner.value, afterInner.value)
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
        @Context var counter: Counter
        @Context var config: TestConfig

        func run(_ input: String) async throws -> String {
            return "\(config.name): \(input) (counter=\(counter.value), retries=\(config.maxRetries))"
        }
    }

    @Test("Step accesses multiple context types")
    func stepAccessesMultipleContexts() async throws {
        let step = MultiContextStep()
        let config = TestConfig(name: "TestRunner", maxRetries: 3)

        let result = try await step
            .context(Counter(value: 42))
            .context(config)
            .run("hello")

        #expect(result == "TestRunner: hello (counter=42, retries=3)")
    }
}

// MARK: - Context with Reference Type Tests

@Suite("Context with Reference Type Tests")
struct ContextReferenceTypeTests {

    struct TrackerStep: Step {
        @Context var tracker: URLTracker

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

        let results = try await step
            .context(tracker)
            .run(url1)

        let results2 = try await step
            .context(tracker)
            .run(url2)

        let results3 = try await step
            .context(tracker)
            .run(url1)  // Already visited

        #expect(results == true)
        #expect(results2 == true)
        #expect(results3 == false)
        #expect(tracker.visitedURLs.count == 2)
    }

    @Test("Multiple steps share same tracker via context")
    func multipleStepsShareTracker() async throws {
        let tracker = URLTracker()
        let step1 = TrackerStep()
        let step2 = TrackerStep()

        _ = try await step1.context(tracker).run(URL(string: "https://a.com")!)
        _ = try await step2.context(tracker).run(URL(string: "https://b.com")!)
        _ = try await step1.context(tracker).run(URL(string: "https://c.com")!)

        #expect(tracker.visitedURLs.count == 3)
    }
}

// MARK: - Context Concurrent Access Tests

@Suite("Context Concurrent Access Tests")
struct ContextConcurrentTests {

    @Test("Context is accessible in concurrent tasks")
    func contextInConcurrentTasks() async throws {
        let tracker = URLTracker()

        await withContext(URLTrackerContext.self, value: tracker) {
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

// MARK: - Contextable Protocol Tests

/// Test configuration using @Contextable macro
/// The type must conform to Contextable with a defaultValue
@Contextable
struct CrawlerSettings: Contextable, Equatable {
    static var defaultValue: CrawlerSettings {
        CrawlerSettings(maxDepth: 3, timeout: 30)
    }

    let maxDepth: Int
    let timeout: Int
}

@Suite("Contextable Protocol Tests")
struct ContextableTests {

    @Test("Contextable type has defaultValue")
    func contextableHasDefaultValue() {
        #expect(CrawlerSettings.defaultValue.maxDepth == 3)
        #expect(CrawlerSettings.defaultValue.timeout == 30)
    }

    @Test("Generated ContextKey returns defaultValue")
    func generatedContextKeyDefaultValue() {
        #expect(CrawlerSettingsContext.defaultValue.maxDepth == 3)
        #expect(CrawlerSettingsContext.current.maxDepth == 3)
    }

    @Test("Generated ContextKey works with withContext")
    func generatedContextKeyWithContext() async throws {
        let custom = CrawlerSettings(maxDepth: 10, timeout: 60)

        let result = await withContext(CrawlerSettingsContext.self, value: custom) {
            CrawlerSettingsContext.current
        }

        #expect(result == custom)
        #expect(result.maxDepth == 10)
        #expect(result.timeout == 60)
    }

    @Test("Generated ContextKey restores after withContext")
    func generatedContextKeyRestores() async throws {
        let custom = CrawlerSettings(maxDepth: 10, timeout: 60)

        _ = await withContext(CrawlerSettingsContext.self, value: custom) {
            #expect(CrawlerSettingsContext.current == custom)
        }

        // Should be back to default
        #expect(CrawlerSettingsContext.current.maxDepth == 3)
    }
}

// MARK: - Contextable Step Integration Tests

@Suite("Contextable Step Integration Tests")
struct ContextableStepTests {

    struct SettingsAccessingStep: Step {
        @Context var settings: CrawlerSettings

        func run(_ input: String) async throws -> String {
            "Crawling \(input) with maxDepth=\(settings.maxDepth), timeout=\(settings.timeout)"
        }
    }

    @Test("Step accesses Contextable via generated ContextKey")
    func stepAccessesContextable() async throws {
        let step = SettingsAccessingStep()
        let custom = CrawlerSettings(maxDepth: 5, timeout: 120)

        let result = try await withContext(CrawlerSettingsContext.self, value: custom) {
            try await step.run("example.com")
        }

        #expect(result == "Crawling example.com with maxDepth=5, timeout=120")
    }

    @Test("Step uses .context() modifier")
    func stepUsesContextModifier() async throws {
        let step = SettingsAccessingStep()
        let custom = CrawlerSettings(maxDepth: 8, timeout: 45)

        let result = try await step
            .context(custom)
            .run("modifier.com")

        #expect(result == "Crawling modifier.com with maxDepth=8, timeout=45")
    }

    @Test("Step uses defaultValue when no context provided")
    func stepUsesDefaultValue() async throws {
        let step = SettingsAccessingStep()

        // No withContext - should use defaultValue
        let result = try await step.run("test.com")

        #expect(result == "Crawling test.com with maxDepth=3, timeout=30")
    }

    @Test("Nested steps share Contextable context")
    func nestedStepsShareContextable() async throws {
        struct OuterStep: Step {
            @Context var settings: CrawlerSettings

            func run(_ input: String) async throws -> String {
                let innerResult = try await InnerStep().run(input)
                return "outer(\(settings.maxDepth)) -> \(innerResult)"
            }
        }

        struct InnerStep: Step {
            @Context var settings: CrawlerSettings

            func run(_ input: String) async throws -> String {
                "inner(\(settings.maxDepth))"
            }
        }

        let custom = CrawlerSettings(maxDepth: 7, timeout: 90)
        let result = try await withContext(CrawlerSettingsContext.self, value: custom) {
            try await OuterStep().run("site.com")
        }

        #expect(result == "outer(7) -> inner(7)")
    }
}
