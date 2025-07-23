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
    @Guide(description: "Whether the task is completed")
    let isComplete: Bool
    @Guide(description: "ID of the next task to execute")
    let nextTaskId: String?
    @Guide(description: "Error message if any")
    let error: String?
}
