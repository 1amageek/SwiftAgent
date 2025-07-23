//
//  Writer.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/14.
//

import Foundation
import SwiftAgent
import OpenFoundationModels


public struct Writer: Agent {
    public typealias Input = String
    public typealias Output = String
    
    public init() {}
    
    public var body: some Step<Input, Output> {
        // Simply write a story based on the input
        StringModelStep<String>(
            instructions: """
                You are a creative writer. 
                Write a compelling story based on the user's request.
                Include interesting characters, plot, and theme.
                """
        ) { input in
            input
        }
    }
}