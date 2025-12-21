import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Helpers

/// Test simple counter step
struct LoopCounterStep: Step, Sendable {
    typealias Input = Int
    typealias Output = Int

    func run(_ input: Int) async throws -> Int {
        input + 1
    }
}

// MARK: - Loop Tests

@Suite("Loop Tests")
struct LoopTests {

    @Test("Loop with while condition")
    func loopWithWhileCondition() async throws {
        let loop = Loop(max: 10, step: { _ in
            LoopCounterStep()
        }, while: { value in
            value < 5  // Continue while value is less than 5
        })

        let result = try await loop.run(0)
        #expect(result == 5)
    }

    @Test("Loop with until condition")
    func loopWithUntilCondition() async throws {
        let loop = Loop(max: 10, step: { _ in
            LoopCounterStep()
        }, until: { value in
            value >= 5  // Stop when value is greater than or equal to 5
        })

        let result = try await loop.run(0)
        #expect(result == 5)
    }

    @Test("Infinite loop with while condition")
    func infiniteLoopWithWhileCondition() async throws {
        let loop = Loop(step: { _ in
            LoopCounterStep()
        }, while: { value in
            value < 3  // Continue while value is less than 3
        })

        let result = try await loop.run(0)
        #expect(result == 3)
    }

    @Test("Infinite loop with until condition")
    func infiniteLoopWithUntilCondition() async throws {
        let loop = Loop(step: { _ in
            LoopCounterStep()
        }, until: { value in
            value >= 3  // Stop when value is greater than or equal to 3
        })

        let result = try await loop.run(0)
        #expect(result == 3)
    }

    @Test("Loop with Step-based condition")
    func loopWithStepCondition() async throws {
        let loop = Loop(max: 10, step: { _ in
            LoopCounterStep()
        }, until: {
            Transform<Int, Bool> { value in
                value >= 5
            }
        })

        let result = try await loop.run(0)
        #expect(result == 5)
    }

    @Test("Loop max iterations limit")
    func loopMaxIterations() async throws {
        let loop = Loop(max: 3, step: { _ in
            LoopCounterStep()
        }, while: { _ in
            true  // Always continue
        })

        await #expect(throws: LoopError.self) {
            try await loop.run(0)
        }
    }
}
