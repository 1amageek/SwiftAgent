//
//  MainAgent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/13.
//

import Foundation
import SwiftAgent

public struct MainAgent: Agent {
    
    public init() {}

    public var body: some Step<String, String> {
        Loop { _ in
            WaitForInput(prompt: "You: ")
            StringModelStep<String>(
                instructions: "You are a helpful assistant. Have a conversation with the user."
            ) { input in
                input
            }
            .onOutput { message in
                print("Assistant: \(message)")
            }
        }
    }
}
