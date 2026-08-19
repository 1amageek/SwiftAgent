import Testing
import Foundation
import Synchronization
@testable import SwiftAgent

// MARK: - Test Contextable Types

/// A simple counter for testing
struct Counter: Contextable, Equatable {
    let value: Int

    static var defaultValue: Counter { Counter(value: 0) }
}

/// A configuration for testing
struct TestConfig: Contextable, Equatable {
    let name: String
    let maxRetries: Int

    static var defaultValue: TestConfig { TestConfig(name: "", maxRetries: 0) }
}

/// A tracker for testing shared state
final class URLTracker: Sendable, Contextable {
    static var defaultValue: URLTracker { URLTracker() }

    private let visitedURLsState = Mutex<Set<URL>>([])

    var visitedURLs: Set<URL> {
        visitedURLsState.withLock { $0 }
    }

    func markVisited(_ url: URL) {
        visitedURLsState.withLock { _ = $0.insert(url) }
    }

    func hasVisited(_ url: URL) -> Bool {
        visitedURLsState.withLock { $0.contains(url) }
    }
}

// MARK: - Context Tests

@Suite("Context Tests")
struct ContextTests {

    @Test("Context returns defaultValue by default")
    func contextDefaultValueByDefault() {
        #expect(Counter.current.value == 0)
    }

    @Test("withValue sets value for operation")
    func withValueSetsValue() async throws {
        let result = await Counter.withValue(Counter(value: 42)) {
            Counter.current
        }

        #expect(result.value == 42)
    }

    @Test("withValue restores defaultValue after operation")
    func withValueRestoresAfter() async throws {
        _ = await Counter.withValue(Counter(value: 100)) {
            #expect(Counter.current.value == 100)
        }

        #expect(Counter.current.value == 0)
    }

    @Test("withValue returns operation result")
    func withValueReturnsResult() async throws {
        let result = await Counter.withValue(Counter(value: 10)) {
            Counter.current.value * 2
        }

        #expect(result == 20)
    }

    @Test("withValue propagates errors")
    func withValuePropagatesErrors() async throws {
        struct TestError: Error {}

        await #expect(throws: TestError.self) {
            try await Counter.withValue(Counter(value: 1)) {
                throw TestError()
            }
        }

        #expect(Counter.current.value == 0)
    }

    @Test("defaultValue is used when no context is set")
    func defaultValueIsUsed() async throws {
        #expect(Counter.current.value == 0)
        #expect(TestConfig.current.name == "")
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

    @Test("Nested withValue overrides outer context")
    func nestedWithValueOverrides() async throws {
        let result = await Counter.withValue(Counter(value: 10)) {
            let outer = Counter.current

            let inner = await Counter.withValue(Counter(value: 100)) {
                Counter.current
            }

            let afterInner = Counter.current

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

    @Test("Context value is inherited by child tasks")
    func contextValueIsInheritedByChildTasks() async {
        let values = await Counter.withValue(Counter(value: 42)) {
            await withTaskGroup(of: Int.self, returning: [Int].self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        Counter.current.value
                    }
                }

                var values: [Int] = []
                for await value in group {
                    values.append(value)
                }
                return values
            }
        }

        #expect(values == [42, 42, 42, 42])
        #expect(Counter.current.value == 0)
    }

    @Test("Context is accessible in concurrent tasks")
    func contextInConcurrentTasks() async throws {
        let tracker = URLTracker()

        await URLTracker.withValue(tracker) {
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

/// Test configuration using the default type-indexed context key.
struct CrawlerSettings: Contextable, Equatable {
    let maxDepth: Int
    let timeout: Int

    static var defaultValue: CrawlerSettings {
        CrawlerSettings(maxDepth: 3, timeout: 30)
    }
}

@Suite("Contextable Protocol Tests")
struct ContextableTests {

    @Test("Contextable type has defaultValue")
    func contextableHasDefaultValue() {
        #expect(CrawlerSettings.defaultValue.maxDepth == 3)
        #expect(CrawlerSettings.defaultValue.timeout == 30)
    }

    @Test("Default ContextKey returns defaultValue")
    func defaultContextKeyDefaultValue() {
        #expect(ContextValueKey<CrawlerSettings>.defaultValue.maxDepth == 3)
        #expect(CrawlerSettings.current.maxDepth == 3)
    }

    @Test("Default ContextKey installs a scoped value")
    func defaultContextKeyWithValue() async throws {
        let custom = CrawlerSettings(maxDepth: 10, timeout: 60)

        let result = await CrawlerSettings.withValue(custom) {
            CrawlerSettings.current
        }

        #expect(result == custom)
        #expect(result.maxDepth == 10)
        #expect(result.timeout == 60)
    }

    @Test("Default ContextKey restores its parent scope")
    func defaultContextKeyRestores() async throws {
        let custom = CrawlerSettings(maxDepth: 10, timeout: 60)

        _ = await CrawlerSettings.withValue(custom) {
            #expect(CrawlerSettings.current == custom)
        }

        #expect(CrawlerSettings.current.maxDepth == 3)
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

    @Test("Step accesses Contextable via its default ContextKey")
    func stepAccessesContextable() async throws {
        let step = SettingsAccessingStep()
        let custom = CrawlerSettings(maxDepth: 5, timeout: 120)

        let result = try await CrawlerSettings.withValue(custom) {
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

        // No context is installed, so the Step should use defaultValue.
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
        let result = try await CrawlerSettings.withValue(custom) {
            try await OuterStep().run("site.com")
        }

        #expect(result == "outer(7) -> inner(7)")
    }
}
