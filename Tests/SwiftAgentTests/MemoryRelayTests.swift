import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Memory Tests

@Suite("Memory Tests")
struct MemoryTests {

    @Test("Memory stores initial value")
    func memoryStoresInitialValue() {
        @Memory var counter: Int = 42
        #expect(counter == 42)
    }

    @Test("Memory allows value modification")
    func memoryAllowsModification() {
        @Memory var counter: Int = 0
        counter = 10
        #expect(counter == 10)
    }

    @Test("Memory provides Relay via projected value")
    func memoryProvidesRelay() {
        @Memory var counter: Int = 5
        let relay = $counter

        #expect(relay.wrappedValue == 5)
    }

    @Test("Memory storage is shared across struct copies")
    func memoryStorageIsShared() {
        struct Container {
            @Memory var value: Int = 0
        }

        let container1 = Container()
        let container2 = container1

        // Both containers share the same storage
        container1.value = 42
        #expect(container2.value == 42)

        container2.value = 100
        #expect(container1.value == 100)
    }

    @Test("Memory with complex types")
    func memoryWithComplexTypes() {
        @Memory var items: [String] = []
        items.append("a")
        items.append("b")
        #expect(items == ["a", "b"])
    }

    @Test("Memory with Set")
    func memoryWithSet() {
        @Memory var urls: Set<URL> = []
        let url1 = URL(string: "https://example.com")!
        let url2 = URL(string: "https://test.com")!

        urls.insert(url1)
        urls.insert(url2)
        urls.insert(url1)  // Duplicate

        #expect(urls.count == 2)
    }
}

// MARK: - Relay Tests

@Suite("Relay Tests")
struct RelayTests {

    @Test("Relay provides bidirectional access")
    func relayBidirectionalAccess() {
        @Memory var value: Int = 0
        let relay = $value

        relay.wrappedValue = 42
        #expect(value == 42)
        #expect(relay.wrappedValue == 42)
    }

    @Test("Relay.constant creates immutable relay")
    func relayConstant() {
        let relay = Relay<Int>.constant(100)

        #expect(relay.wrappedValue == 100)
        relay.wrappedValue = 999  // Should be ignored
        #expect(relay.wrappedValue == 100)
    }

    @Test("Relay can be passed to functions")
    func relayPassedToFunction() {
        @Memory var value: Int = 0

        func increment(relay: Relay<Int>) {
            relay.wrappedValue += 1
        }

        increment(relay: $value)
        increment(relay: $value)

        #expect(value == 2)
    }

    @Test("Relay projectedValue returns self")
    func relayProjectedValueReturnsSelf() {
        @Memory var value: Int = 10
        let relay = $value
        let projected = relay.projectedValue

        projected.wrappedValue = 20
        #expect(value == 20)
    }

    @Test("Relay from projectedValue initializer")
    func relayFromProjectedValue() {
        @Memory var value: Int = 5
        let relay = Relay(projectedValue: $value)

        relay.wrappedValue = 15
        #expect(value == 15)
    }
}

// MARK: - Relay Optional Support Tests

@Suite("Relay Optional Support Tests")
struct RelayOptionalTests {

    @Test("Relay wraps non-optional as optional")
    func relayWrapsAsOptional() {
        @Memory var value: Int = 42
        let optionalRelay = Relay<Int?>($value)

        #expect(optionalRelay.wrappedValue == 42)

        optionalRelay.wrappedValue = 100
        #expect(value == 100)
    }

    @Test("Relay unwraps optional to non-optional")
    func relayUnwrapsOptional() {
        @Memory var optionalValue: Int? = 42
        let nonOptionalRelay = Relay($optionalValue)

        #expect(nonOptionalRelay != nil)
        #expect(nonOptionalRelay?.wrappedValue == 42)
    }

    @Test("Relay unwrap returns nil for nil value")
    func relayUnwrapReturnsNil() {
        @Memory var optionalValue: Int? = nil
        let nonOptionalRelay = Relay($optionalValue)

        #expect(nonOptionalRelay == nil)
    }
}

// MARK: - Relay Transformation Tests

@Suite("Relay Transformation Tests")
struct RelayTransformationTests {

    @Test("Relay map transforms value bidirectionally")
    func relayMapTransforms() {
        @Memory var celsius: Double = 0.0
        let fahrenheitRelay = $celsius.map(
            { $0 * 9 / 5 + 32 },
            reverse: { ($0 - 32) * 5 / 9 }
        )

        // 0°C = 32°F
        #expect(fahrenheitRelay.wrappedValue == 32.0)

        // Set to 212°F = 100°C
        fahrenheitRelay.wrappedValue = 212.0
        #expect(celsius == 100.0)
    }

    @Test("Relay readOnly creates read-only relay")
    func relayReadOnly() {
        @Memory var value: Int = 10
        let readOnly = $value.readOnly { $0 * 2 }

        #expect(readOnly.wrappedValue == 20)

        readOnly.wrappedValue = 999  // Should be ignored
        #expect(value == 10)  // Original unchanged
        #expect(readOnly.wrappedValue == 20)  // Still reflects original
    }
}

// MARK: - Relay Collection Extensions Tests

@Suite("Relay Collection Extensions Tests")
struct RelayCollectionTests {

    @Test("Relay append for arrays")
    func relayAppendArray() {
        @Memory var items: [String] = []
        $items.append("first")
        $items.append("second")

        #expect(items == ["first", "second"])
    }

    @Test("Relay append contentsOf for arrays")
    func relayAppendContentsOf() {
        @Memory var items: [Int] = [1, 2]
        $items.append(contentsOf: [3, 4, 5])

        #expect(items == [1, 2, 3, 4, 5])
    }

    @Test("Relay removeAll for arrays")
    func relayRemoveAll() {
        @Memory var items: [String] = ["a", "b", "c"]
        $items.removeAll()

        #expect(items.isEmpty)
    }

    @Test("Relay insert for sets")
    func relayInsertSet() {
        @Memory var items: Set<Int> = []
        let (inserted1, _) = $items.insert(1)
        let (inserted2, _) = $items.insert(1)  // Duplicate

        #expect(inserted1 == true)
        #expect(inserted2 == false)
        #expect(items.count == 1)
    }

    @Test("Relay remove for sets")
    func relayRemoveSet() {
        @Memory var items: Set<Int> = [1, 2, 3]
        let removed = $items.remove(2)

        #expect(removed == 2)
        #expect(items == [1, 3])
    }

    @Test("Relay contains for sets")
    func relayContainsSet() {
        @Memory var items: Set<String> = ["apple", "banana"]

        #expect($items.contains("apple") == true)
        #expect($items.contains("orange") == false)
    }

    @Test("Relay formUnion for sets")
    func relayFormUnion() {
        @Memory var items: Set<Int> = [1, 2]
        $items.formUnion([2, 3, 4])

        #expect(items == [1, 2, 3, 4])
    }
}

// MARK: - Relay Int Extensions Tests

@Suite("Relay Int Extensions Tests")
struct RelayIntTests {

    @Test("Relay increment")
    func relayIncrement() {
        @Memory var counter: Int = 0
        $counter.increment()
        $counter.increment()

        #expect(counter == 2)
    }

    @Test("Relay decrement")
    func relayDecrement() {
        @Memory var counter: Int = 10
        $counter.decrement()

        #expect(counter == 9)
    }

    @Test("Relay add")
    func relayAdd() {
        @Memory var counter: Int = 5
        $counter.add(10)

        #expect(counter == 15)
    }
}

// MARK: - Memory/Relay with Steps Tests

@Suite("Memory/Relay with Steps Tests")
struct MemoryRelayStepTests {

    /// Step that uses Relay to track visited items
    struct TrackingStep: Step {
        let relay: Relay<Set<Int>>

        func run(_ input: Int) async throws -> Bool {
            if relay.contains(input) {
                return false
            }
            relay.insert(input)
            return true
        }
    }

    @Test("Step uses Relay for state sharing")
    func stepUsesRelay() async throws {
        @Memory var visited: Set<Int> = []
        let step = TrackingStep(relay: $visited)

        let result1 = try await step.run(1)
        let result2 = try await step.run(2)
        let result3 = try await step.run(1)  // Already visited

        #expect(result1 == true)
        #expect(result2 == true)
        #expect(result3 == false)
        #expect(visited == [1, 2])
    }

    /// Step that counts execution
    struct CountingStep: Step {
        let counter: Relay<Int>

        func run(_ input: String) async throws -> String {
            counter.increment()
            return "\(input) (call #\(counter.wrappedValue))"
        }
    }

    @Test("Multiple steps share counter via Relay")
    func multipleStepsShareRelay() async throws {
        @Memory var counter: Int = 0
        let step1 = CountingStep(counter: $counter)
        let step2 = CountingStep(counter: $counter)

        _ = try await step1.run("a")
        _ = try await step2.run("b")
        let result = try await step1.run("c")

        #expect(counter == 3)
        #expect(result == "c (call #3)")
    }

    /// Orchestrator step that manages child steps with shared state
    struct OrchestratorStep: Step {
        @Memory var processedCount: Int = 0

        func run(_ input: [String]) async throws -> Int {
            for item in input {
                try await ProcessStep(counter: $processedCount).run(item)
            }
            return processedCount
        }
    }

    struct ProcessStep: Step {
        let counter: Relay<Int>

        func run(_ input: String) async throws -> Void {
            // Simulate processing
            counter.increment()
        }
    }

    @Test("Orchestrator shares state with child steps")
    func orchestratorSharesState() async throws {
        let step = OrchestratorStep()
        let result = try await step.run(["a", "b", "c", "d"])

        #expect(result == 4)
    }
}
