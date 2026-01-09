import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Event Names

extension EventName {
    static let testStarted = EventName("testStarted")
    static let testCompleted = EventName("testCompleted")
    static let testFailed = EventName("testFailed")
}

// MARK: - Test Helper

actor TestEventCollector {
    var payloads: [EventBus.Payload] = []
    var names: [EventName] = []
    var values: [String] = []
    var order: [String] = []
    var count: Int = 0

    func append(_ payload: EventBus.Payload) {
        payloads.append(payload)
        names.append(payload.name)
        if let value = payload.value as? String {
            values.append(value)
        }
    }

    func appendOrder(_ item: String) {
        order.append(item)
    }

    func increment() {
        count += 1
    }
}

// MARK: - EventName Tests

@Suite("EventName Tests")
struct EventNameTests {

    @Test("EventName equality")
    func eventNameEquality() {
        let name1 = EventName("test")
        let name2 = EventName("test")
        let name3 = EventName("other")

        #expect(name1 == name2)
        #expect(name1 != name3)
    }

    @Test("EventName hashable")
    func eventNameHashable() {
        var set: Set<EventName> = []
        set.insert(.testStarted)
        set.insert(.testStarted)
        set.insert(.testCompleted)

        #expect(set.count == 2)
    }

    @Test("Static event names")
    func staticEventNames() {
        #expect(EventName.testStarted.rawValue == "testStarted")
        #expect(EventName.testCompleted.rawValue == "testCompleted")
    }
}

// MARK: - EventBus Tests

@Suite("EventBus Tests")
struct EventBusTests {

    @Test("EventBus emits to registered handler")
    func eventBusEmitsToHandler() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { payload in
            await collector.append(payload)
        }

        await eventBus.emit(.testStarted)

        let names = await collector.names
        #expect(names == [.testStarted])
    }

    @Test("EventBus emits with payload")
    func eventBusEmitsWithPayload() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testCompleted) { payload in
            await collector.append(payload)
        }

        await eventBus.emit(.testCompleted, value: "success")

        let payloads = await collector.payloads
        #expect(payloads.first?.name == .testCompleted)
        #expect(payloads.first?.value as? String == "success")
    }

    @Test("EventBus multiple handlers")
    func eventBusMultipleHandlers() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { _ in await collector.increment() }
        await eventBus.on(.testStarted) { _ in await collector.increment() }
        await eventBus.on(.testStarted) { _ in await collector.increment() }

        await eventBus.emit(.testStarted)

        let count = await collector.count
        #expect(count == 3)
    }

    @Test("EventBus different events")
    func eventBusDifferentEvents() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { payload in await collector.append(payload) }
        await eventBus.on(.testCompleted) { payload in await collector.append(payload) }

        await eventBus.emit(.testStarted)
        await eventBus.emit(.testStarted)
        await eventBus.emit(.testCompleted)

        let names = await collector.names
        #expect(names.filter { $0 == .testStarted }.count == 2)
        #expect(names.filter { $0 == .testCompleted }.count == 1)
    }

    @Test("EventBus off removes handlers")
    func eventBusOffRemovesHandlers() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { _ in await collector.increment() }
        await eventBus.emit(.testStarted)

        let countBefore = await collector.count
        #expect(countBefore == 1)

        await eventBus.off(.testStarted)
        await eventBus.emit(.testStarted)

        let countAfter = await collector.count
        #expect(countAfter == 1)  // Still 1, handler was removed
    }

    @Test("EventBus removeAllHandlers")
    func eventBusRemoveAllHandlers() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { _ in await collector.increment() }
        await eventBus.on(.testCompleted) { _ in await collector.increment() }

        await eventBus.removeAllHandlers()

        await eventBus.emit(.testStarted)
        await eventBus.emit(.testCompleted)

        let count = await collector.count
        #expect(count == 0)
    }

    @Test("EventBus no handler for event")
    func eventBusNoHandler() async {
        let eventBus = EventBus()
        // Should not crash when emitting without handlers
        await eventBus.emit(.testStarted)
    }
}

// MARK: - EmittingStep Tests

@Suite("EmittingStep Tests")
struct EmittingStepTests {

    @Test("emit after step execution")
    func emitAfterExecution() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testCompleted) { payload in
            await collector.append(payload)
        }

        let step = Transform<String, String> { $0.uppercased() }
            .emit(.testCompleted)

        let result = try await EventBusContext.withValue(eventBus) {
            try await step.run("hello")
        }

        #expect(result == "HELLO")
        let names = await collector.names
        #expect(names == [.testCompleted])
    }

    @Test("emit before step execution")
    func emitBeforeExecution() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { payload in
            await collector.append(payload)
        }

        let step = Transform<String, String> { input in
            // Note: We can't easily track order here in sync transform
            // but we verify the event was emitted
            return input.uppercased()
        }.emit(.testStarted, on: .before)

        let result = try await EventBusContext.withValue(eventBus) {
            try await step.run("hello")
        }

        #expect(result == "HELLO")
        let names = await collector.names
        #expect(names == [.testStarted])
    }

    @Test("emit with payload")
    func emitWithPayload() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testCompleted) { payload in
            await collector.append(payload)
        }

        let step = Transform<String, String> { $0.uppercased() }
            .emit(.testCompleted) { output in output }

        _ = try await EventBusContext.withValue(eventBus) {
            try await step.run("hello")
        }

        let payloads = await collector.payloads
        #expect(payloads.first?.value as? String == "HELLO")
    }

    @Test("chained emit calls")
    func chainedEmitCalls() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { payload in await collector.append(payload) }
        await eventBus.on(.testCompleted) { payload in await collector.append(payload) }

        let step = Transform<String, String> { $0.uppercased() }
            .emit(.testStarted, on: .before)
            .emit(.testCompleted, on: .after)

        _ = try await EventBusContext.withValue(eventBus) {
            try await step.run("hello")
        }

        let names = await collector.names
        #expect(names == [.testStarted, .testCompleted])
    }

    @Test("emit default timing is after")
    func emitDefaultTimingIsAfter() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testCompleted) { payload in
            await collector.append(payload)
        }

        let step = Transform<String, String> { input in
            return input
        }.emit(.testCompleted)  // No timing specified, should be .after

        _ = try await EventBusContext.withValue(eventBus) {
            try await step.run("test")
        }

        let names = await collector.names
        #expect(names == [.testCompleted])
    }
}

// MARK: - Integration Tests

@Suite("Event Integration Tests")
struct EventIntegrationTests {

    @Test("Event in Agent body")
    func eventInAgentBody() async throws {
        struct TestAgent: Agent {
            var body: some Step<String, String> {
                Transform<String, String> { $0.lowercased() }
                    .emit(.testStarted, on: .before)
                Transform<String, String> { "[\($0)]" }
                    .emit(.testCompleted, on: .after)
            }
        }

        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { payload in await collector.append(payload) }
        await eventBus.on(.testCompleted) { payload in await collector.append(payload) }

        let result = try await EventBusContext.withValue(eventBus) {
            try await TestAgent().run("HELLO")
        }

        #expect(result == "[hello]")
        let names = await collector.names
        #expect(names == [.testStarted, .testCompleted])
    }

    @Test("Event with Pipeline")
    func eventWithPipeline() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { payload in await collector.append(payload) }
        await eventBus.on(.testCompleted) { payload in await collector.append(payload) }

        let pipeline = Pipeline {
            Transform<Int, Int> { $0 * 2 }
                .emit(.testStarted, on: .before)
            Transform<Int, String> { "Result: \($0)" }
                .emit(.testCompleted) { $0 }
        }

        let result = try await EventBusContext.withValue(eventBus) {
            try await pipeline.run(5)
        }

        #expect(result == "Result: 10")
        let names = await collector.names
        #expect(names == [.testStarted, .testCompleted])

        let payloads = await collector.payloads
        #expect(payloads.last?.value as? String == "Result: 10")
    }

    @Test("Event with Gate")
    func eventWithGate() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        await eventBus.on(.testStarted) { payload in await collector.append(payload) }
        await eventBus.on(.testCompleted) { payload in await collector.append(payload) }

        let gate = Gate<String, String> { input in
            .pass(input.uppercased())
        }
        .emit(.testStarted, on: .before)
        .emit(.testCompleted, on: .after)

        let result = try await EventBusContext.withValue(eventBus) {
            try await gate.run("hello")
        }

        #expect(result == "HELLO")
        let names = await collector.names
        #expect(names == [.testStarted, .testCompleted])
    }
}
