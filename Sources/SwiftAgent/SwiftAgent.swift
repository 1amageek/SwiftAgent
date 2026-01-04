//
//  SwiftAgent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/12.
//

#if USE_OTHER_MODELS
@_exported import OpenFoundationModels
#else
@_exported import FoundationModels
#endif

/// Framework information
public enum Info {
    /// The name of the framework
    public static let name = "SwiftAgent"

    /// The version of the framework
    public static let version = "1.0.0"
}
