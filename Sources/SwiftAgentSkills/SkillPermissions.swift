//
//  SkillPermissions.swift
//  SwiftAgent
//
//  Holds permission rules granted by activated skills.
//

import Foundation
import SwiftAgent

/// Holds permission rules granted by activated skills.
///
/// This class accumulates permission rules from skills as they are activated
/// during a session. The rules are added to the allow list when evaluating
/// tool permissions.
///
/// ## Usage
///
/// ```swift
/// let permissions = SkillPermissions()
///
/// // When a skill is activated, add its allowed-tools
/// let rules = PermissionRule.parse("Bash(git:*) Read")
/// permissions.add(rules, from: "git-workflow")
///
/// // PermissionMiddleware reads these rules
/// let allowedRules = permissions.rules
/// ```
///
/// ## Thread Safety
///
/// All methods are thread-safe using `NSLock`.
///
/// ## Reference Counting
///
/// If multiple skills grant the same permission, the permission remains active
/// until all skills that granted it are removed. This prevents one skill's
/// deactivation from revoking permissions still needed by another skill.
public final class SkillPermissions: @unchecked Sendable {

    private let lock = NSLock()
    private var _rulesBySkill: [String: [PermissionRule]] = [:]
    /// Reference count for each rule pattern (how many skills grant it)
    private var _ruleRefCount: [String: Int] = [:]

    /// Creates an empty skill permissions container.
    public init() {}

    /// The accumulated permission rules from all activated skills.
    ///
    /// Returns unique rules - if multiple skills grant the same pattern,
    /// it appears only once in the result.
    public var rules: [PermissionRule] {
        lock.withLock {
            // Return unique rules based on pattern
            Array(_ruleRefCount.keys).map { PermissionRule($0) }
        }
    }

    /// Returns permission rules granted by a specific skill.
    ///
    /// - Parameter skillName: The name of the skill.
    /// - Returns: Array of permission rules from that skill.
    public func rules(from skillName: String) -> [PermissionRule] {
        lock.withLock { _rulesBySkill[skillName] ?? [] }
    }

    /// The names of skills that have granted permissions.
    public var skillNames: [String] {
        lock.withLock { Array(_rulesBySkill.keys).sorted() }
    }

    /// Adds permission rules.
    ///
    /// - Parameter rules: The rules to add.
    public func add(_ rules: [PermissionRule]) {
        guard !rules.isEmpty else { return }
        lock.withLock {
            for rule in rules {
                _ruleRefCount[rule.pattern, default: 0] += 1
            }
        }
    }

    /// Adds permission rules from a specific skill.
    ///
    /// This method tracks which skill granted which permissions,
    /// useful for auditing and debugging. If multiple skills grant
    /// the same permission, it remains active until all skills that
    /// granted it are removed.
    ///
    /// - Parameters:
    ///   - rules: The rules to add.
    ///   - skillName: The name of the skill granting these permissions.
    public func add(_ rules: [PermissionRule], from skillName: String) {
        guard !rules.isEmpty else { return }
        lock.withLock {
            _rulesBySkill[skillName, default: []].append(contentsOf: rules)
            for rule in rules {
                _ruleRefCount[rule.pattern, default: 0] += 1
            }
        }
    }

    /// Removes all permission rules granted by a specific skill.
    ///
    /// If another skill also granted the same permission, it remains active.
    /// Only when all skills that granted a permission are removed will
    /// the permission be revoked.
    ///
    /// - Parameter skillName: The name of the skill to remove.
    public func remove(from skillName: String) {
        lock.withLock {
            guard let skillRules = _rulesBySkill.removeValue(forKey: skillName) else {
                return
            }
            // Decrement reference count for each rule
            for rule in skillRules {
                if let count = _ruleRefCount[rule.pattern] {
                    if count <= 1 {
                        _ruleRefCount.removeValue(forKey: rule.pattern)
                    } else {
                        _ruleRefCount[rule.pattern] = count - 1
                    }
                }
            }
        }
    }

    /// Clears all permission rules.
    public func clear() {
        lock.withLock {
            _rulesBySkill.removeAll()
            _ruleRefCount.removeAll()
        }
    }

    /// The number of unique permission rules.
    public var count: Int {
        lock.withLock { _ruleRefCount.count }
    }

    /// Whether there are any permission rules.
    public var isEmpty: Bool {
        lock.withLock { _ruleRefCount.isEmpty }
    }
}

// MARK: - CustomStringConvertible

extension SkillPermissions: CustomStringConvertible {
    public var description: String {
        let ruleCount = count
        let skillCount = lock.withLock { _rulesBySkill.count }
        return "SkillPermissions(\(ruleCount) rules from \(skillCount) skills)"
    }
}
