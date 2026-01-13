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
    var events: [any Event] = []
    var names: [EventName] = []
    var values: [String] = []
    var stepNames: [String] = []
    var order: [String] = []
    var count: Int = 0

    func append(_ event: any Event) {
        events.append(event)
        names.append(event.name)

        // Extract value from concrete event types
        if let stepEvent = event as? StepEvent {
            stepNames.append(stepEvent.stepName)
            if let value = stepEvent.value as? String {
                values.append(value)
            }
        } else if let sessionEvent = event as? SessionEvent {
            if let value = sessionEvent.value as? String {
                values.append(value)
            }
        } else if let agentEvent = event as? AgentEvent {
            if let value = agentEvent.value as? String {
                values.append(value)
            }
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

    @Test("Standard event names")
    func standardEventNames() {
        #expect(EventName.promptSubmitted.rawValue == "promptSubmitted")
        #expect(EventName.responseCompleted.rawValue == "responseCompleted")
    }
}

// MARK: - Event Protocol Tests

@Suite("Event Protocol Tests")
struct EventProtocolTests {

    @Test("SessionEvent conforms to Event")
    func sessionEventConforms() {
        let event = SessionEvent(
            name: .testStarted,
            sessionID: "session-123",
            value: "test value"
        )

        #expect(event.name == .testStarted)
        #expect(event.sessionID == "session-123")
        #expect(event.value as? String == "test value")
        #expect(event.timestamp <= Date())
    }

    @Test("StepEvent conforms to Event")
    func stepEventConforms() {
        let event = StepEvent(
            name: .testCompleted,
            stepName: "MyStep",
            value: "step result"
        )

        #expect(event.name == .testCompleted)
        #expect(event.stepName == "MyStep")
        #expect(event.value as? String == "step result")
        #expect(event.timestamp <= Date())
    }

    @Test("AgentEvent conforms to Event")
    func agentEventConforms() {
        let event = AgentEvent(
            name: .testFailed,
            agentID: "agent-456",
            value: "error message"
        )

        #expect(event.name == .testFailed)
        #expect(event.agentID == "agent-456")
        #expect(event.value as? String == "error message")
        #expect(event.timestamp <= Date())
    }
}

// MARK: - EventBus Tests

@Suite("EventBus Tests")
struct EventBusTests {

    @Test("EventBus emits to registered handler")
    func eventBusEmitsToHandler() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { event in
            await collector.append(event)
        }

        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))

        let names = await collector.names
        #expect(names == [.testStarted])
    }

    @Test("EventBus emits with payload")
    func eventBusEmitsWithPayload() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testCompleted) { event in
            await collector.append(event)
        }

        await eventBus.emit(StepEvent(name: .testCompleted, stepName: "Test", value: "success"))

        let events = await collector.events
        #expect(events.first?.name == .testCompleted)
        if let stepEvent = events.first as? StepEvent {
            #expect(stepEvent.value as? String == "success")
        } else {
            Issue.record("Expected StepEvent")
        }
    }

    @Test("EventBus multiple handlers")
    func eventBusMultipleHandlers() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { _ in await collector.increment() }
        eventBus.on(.testStarted) { _ in await collector.increment() }
        eventBus.on(.testStarted) { _ in await collector.increment() }

        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))

        let count = await collector.count
        #expect(count == 3)
    }

    @Test("EventBus different events")
    func eventBusDifferentEvents() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { event in await collector.append(event) }
        eventBus.on(.testCompleted) { event in await collector.append(event) }

        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))
        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))
        await eventBus.emit(StepEvent(name: .testCompleted, stepName: "Test"))

        let names = await collector.names
        #expect(names.filter { $0 == .testStarted }.count == 2)
        #expect(names.filter { $0 == .testCompleted }.count == 1)
    }

    @Test("EventBus off removes handlers")
    func eventBusOffRemovesHandlers() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { _ in await collector.increment() }
        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))

        let countBefore = await collector.count
        #expect(countBefore == 1)

        eventBus.off(.testStarted)
        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))

        let countAfter = await collector.count
        #expect(countAfter == 1)  // Still 1, handler was removed
    }

    @Test("EventBus removeAllHandlers")
    func eventBusRemoveAllHandlers() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { _ in await collector.increment() }
        eventBus.on(.testCompleted) { _ in await collector.increment() }

        eventBus.removeAllHandlers()

        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))
        await eventBus.emit(StepEvent(name: .testCompleted, stepName: "Test"))

        let count = await collector.count
        #expect(count == 0)
    }

    @Test("EventBus no handler for event")
    func eventBusNoHandler() async {
        let eventBus = EventBus()
        // Should not crash when emitting without handlers
        await eventBus.emit(StepEvent(name: .testStarted, stepName: "Test"))
    }

    @Test("EventBus handles different event types")
    func eventBusHandlesDifferentEventTypes() async {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { event in await collector.append(event) }

        // Emit different event types with same name
        await eventBus.emit(SessionEvent(name: .testStarted, sessionID: "session-1"))
        await eventBus.emit(StepEvent(name: .testStarted, stepName: "MyStep"))
        await eventBus.emit(AgentEvent(name: .testStarted, agentID: "agent-1"))

        let events = await collector.events
        #expect(events.count == 3)
        #expect(events[0] is SessionEvent)
        #expect(events[1] is StepEvent)
        #expect(events[2] is AgentEvent)
    }
}

// MARK: - EmittingStep Tests

@Suite("EmittingStep Tests")
struct EmittingStepTests {

    @Test("emit after step execution")
    func emitAfterExecution() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testCompleted) { event in
            await collector.append(event)
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

        eventBus.on(.testStarted) { event in
            await collector.append(event)
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

        eventBus.on(.testCompleted) { event in
            await collector.append(event)
        }

        let step = Transform<String, String> { $0.uppercased() }
            .emit(.testCompleted) { output in output }

        _ = try await EventBusContext.withValue(eventBus) {
            try await step.run("hello")
        }

        let events = await collector.events
        if let stepEvent = events.first as? StepEvent {
            #expect(stepEvent.value as? String == "HELLO")
        } else {
            Issue.record("Expected StepEvent with value")
        }
    }

    @Test("chained emit calls")
    func chainedEmitCalls() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { event in await collector.append(event) }
        eventBus.on(.testCompleted) { event in await collector.append(event) }

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

        eventBus.on(.testCompleted) { event in
            await collector.append(event)
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

    @Test("emit includes step name")
    func emitIncludesStepName() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testCompleted) { event in
            await collector.append(event)
        }

        let step = Transform<String, String> { $0.uppercased() }
            .emit(.testCompleted)

        _ = try await EventBusContext.withValue(eventBus) {
            try await step.run("hello")
        }

        let stepNames = await collector.stepNames
        #expect(stepNames.count == 1)
        #expect(stepNames.first?.contains("Transform") == true)
    }
}

// MARK: - Integration Tests

@Suite("Event Integration Tests")
struct EventIntegrationTests {

    @Test("Event in declarative Step body")
    func eventInDeclarativeStepBody() async throws {
        struct TestStep: Step {
            var body: some Step<String, String> {
                Transform<String, String> { $0.lowercased() }
                    .emit(.testStarted, on: .before)
                Transform<String, String> { "[\($0)]" }
                    .emit(.testCompleted, on: .after)
            }
        }

        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { event in await collector.append(event) }
        eventBus.on(.testCompleted) { event in await collector.append(event) }

        let result = try await EventBusContext.withValue(eventBus) {
            try await TestStep().run("HELLO")
        }

        #expect(result == "[hello]")
        let names = await collector.names
        #expect(names == [.testStarted, .testCompleted])
    }

    @Test("Event with Pipeline")
    func eventWithPipeline() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { event in await collector.append(event) }
        eventBus.on(.testCompleted) { event in await collector.append(event) }

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

        let events = await collector.events
        if let lastEvent = events.last as? StepEvent {
            #expect(lastEvent.value as? String == "Result: 10")
        } else {
            Issue.record("Expected StepEvent with value")
        }
    }

    @Test("Event with Gate")
    func eventWithGate() async throws {
        let eventBus = EventBus()
        let collector = TestEventCollector()

        eventBus.on(.testStarted) { event in await collector.append(event) }
        eventBus.on(.testCompleted) { event in await collector.append(event) }

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
