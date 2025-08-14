import XCTest
@testable import SwiftAgent

final class LoopTests: XCTestCase {
    
    // Test simple counter step
    struct CounterStep: Step {
        typealias Input = Int
        typealias Output = Int
        
        func run(_ input: Int) async throws -> Int {
            return input + 1
        }
    }
    
    // Test the "while" condition (continues while condition is true)
    func testLoopWithWhileCondition() async throws {
        let loop = Loop(max: 10, step: { _ in
            CounterStep()
        }, while: { value in
            value < 5  // Continue while value is less than 5
        })
        
        let result = try await loop.run(0)
        XCTAssertEqual(result, 5, "Loop should stop when value reaches 5")
    }
    
    // Test the "until" condition (stops when condition is true)
    func testLoopWithUntilCondition() async throws {
        let loop = Loop(max: 10, step: { _ in
            CounterStep()
        }, until: { value in
            value >= 5  // Stop when value is greater than or equal to 5
        })
        
        let result = try await loop.run(0)
        XCTAssertEqual(result, 5, "Loop should stop when value reaches 5")
    }
    
    // Test infinite loop with "while" condition
    func testInfiniteLoopWithWhileCondition() async throws {
        let loop = Loop(step: { _ in
            CounterStep()
        }, while: { value in
            value < 3  // Continue while value is less than 3
        })
        
        let result = try await loop.run(0)
        XCTAssertEqual(result, 3, "Loop should stop when value reaches 3")
    }
    
    // Test infinite loop with "until" condition
    func testInfiniteLoopWithUntilCondition() async throws {
        let loop = Loop(step: { _ in
            CounterStep()
        }, until: { value in
            value >= 3  // Stop when value is greater than or equal to 3
        })
        
        let result = try await loop.run(0)
        XCTAssertEqual(result, 3, "Loop should stop when value reaches 3")
    }
    
    // Test that Step-based conditions still work
    func testLoopWithStepCondition() async throws {
        let loop = Loop(max: 10, step: { _ in
            CounterStep()
        }, until: {
            Transform<Int, Bool> { value in
                value >= 5
            }
        })
        
        let result = try await loop.run(0)
        XCTAssertEqual(result, 5, "Loop should stop when value reaches 5")
    }
    
    // Test max iterations limit
    func testLoopMaxIterations() async throws {
        let loop = Loop(max: 3, step: { _ in
            CounterStep()
        }, while: { _ in
            true  // Always continue
        })
        
        do {
            _ = try await loop.run(0)
            XCTFail("Loop should throw conditionNotMet error")
        } catch LoopError.conditionNotMet {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}