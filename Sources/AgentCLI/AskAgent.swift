//
//  AskAgent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation
import SwiftAgent

public struct AskAgent: Agent {
    
    public init() {}
    
    public var body: some Step<String, String> {
        Loop(max: 3) { _ in
            StringModelStep<String>(
                instructions: "You are a helpful assistant."
            ) { input in
                input
            }
            .onOutput { message in
                print(message)
            }
        } until: {
            Transform<String, Bool> { message in
                message.lowercased().contains("exit") || message.lowercased().contains("quit")
            }
        }
    }
}
