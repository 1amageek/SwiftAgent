//
//  TaskCompletion.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/17.
//

import Foundation
import OpenFoundationModels

/// タスクの完了状態を表す構造体
@Generable
public struct TaskCompletion {
    @Guide(description: "ID of the next task to execute (empty string if none)")
    let nextTaskId: String
    @Guide(description: "Error message (empty string if no error)")
    let error: String
}
