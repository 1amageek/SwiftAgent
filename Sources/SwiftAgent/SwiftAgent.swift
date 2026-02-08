//
//  SwiftAgent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/12.
//

#if OpenFoundationModels
@_exported import OpenFoundationModels
@_exported import OpenFoundationModelsExtra
public typealias Tool = OpenFoundationModels.Tool
#else
@_exported import FoundationModels
public typealias Tool = FoundationModels.Tool
#endif

/// Framework information
public enum Info {
    /// The name of the framework
    public static let name = "SwiftAgent"

    /// The version of the framework
    public static let version = "1.0.0"
}
