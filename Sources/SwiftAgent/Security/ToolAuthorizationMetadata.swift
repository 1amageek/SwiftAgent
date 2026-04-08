//
//  ToolAuthorizationMetadata.swift
//  SwiftAgent
//

import Foundation

/// Shared metadata keys used to influence generic permission handling.
public enum ToolAuthorizationMetadata {
    public static let decisionKey = "swiftagent.authorizationDecision"
    public static let reasonKey = "swiftagent.authorizationReason"
    public static let minimumPermissionModeKey = "swiftagent.minimumPermissionMode"
}
