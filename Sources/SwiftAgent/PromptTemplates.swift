import Foundation

/// A structure to generate system prompts for AI agents.
public struct PromptTemplates {
    
    /// Generates the complete system prompt.
    ///
    /// - Parameters:
    ///   - tools: An array of available tools.
    ///   - workingDirectory: The current working directory.
    ///   - systemInfo: The system information.
    /// - Returns: A formatted system prompt as a `String`.
    public static func systemPrompt(
        tools: [any Tool],
        workingDirectory: String,
        systemInfo: SystemInfo
    ) -> String {
        """
        \(roleDescription())
        
        \(systemInfo.description)
        
        ===
        
        \(toolUsageGuide(tools: tools))
        
        ---
        
        \(executionProcess())
        """
    }
    
    /// Describes the role and capabilities of the AI agent.
    ///
    /// - Returns: A description of the AI agent's role.
    static func roleDescription() -> String {
        """
        You are an AI agent with advanced capabilities in problem-solving and task execution.  
        You and the system, including tools, are recognized as a unified entity.  
        Your approach is systematic (Chain of Thought):  
        
        1. Break down tasks into clear, logical steps.  
        2. At each step, consider whether you can solve the problem with reasoning alone or if you require external data or actions.  
        3. If a step is difficult to execute, consider whether it can be achieved using a tool.  
        4. Execute each step precisely to achieve the desired outcome.  
        
        You have access to system tools, which are also part of yourself, but use them **only when absolutely necessary**.  
        
        When using tools:  
        - First, analyze the task requirements to determine if the tool (part of you) is truly required.  
        - If a tool is needed, choose the most appropriate one for the specific step.  
        - Clearly explain why the tool is needed and how it will be used before execution.  
        
        **Follow the available tools listed in SYSTEM INFORMATION as part of your capabilities.**  
        **Respond in the same language as the user's query.**
        """
    }
    
    /// Provides a guide for tool usage.
    ///
    /// - Parameter tools: An array of available tools.
    /// - Returns: A formatted guide for available tools and usage rules.
    static func toolUsageGuide(tools: [any Tool]) -> String {
        """
        [AVAILABLE TOOLS]:
        \(formatToolDescriptions(tools))
        
        [TOOL USAGE RULES]:
        1. Use tools only when required; avoid using tools for simple reasoning, basic instructions, or trivial tasks (e.g., greetings).
        2. Use only one tool at a time.
        3. Format each tool use with proper XML tags (e.g., <tool></tool>).
        4. Wait for success confirmation after each tool use.
        5. Think through each step carefully before proceeding.
        6. Provide clear explanations for actions, especially for commands.
        
        IMPORTANT: The following tool descriptions and examples are for reference only, and do NOT imply mandatory usage.
        Use a tool only if your Chain of Thought determines it is absolutely needed.
        """
    }
    
    /// Describes the process guidelines for task execution.
    ///
    /// - Returns: A formatted guide for task execution.
    static func executionProcess() -> String {
        """
        [EXECUTION PROCESS]:
        1. Analyze each user request thoroughly using <thinking></thinking> tags.
           - Break the request into logical steps (Chain of Thought).
           - Evaluate whether the request can be handled with reasoning alone or requires a tool (e.g., to fetch external data).
        2. If the request can be answered without a tool, proceed directly. For simple tasks like greetings or short answers, respond promptly and concisely.
        3. If a tool is required, select the most appropriate one for each step.
        4. Execute tools one at a time, waiting for confirmation before proceeding.
        5. If the tool results influence the next step, incorporate them into your reasoning (<thinking></thinking>) before deciding further actions.
        6. Adjust your approach based on results or feedback.
        7. Present final results clearly and concisely.
        """
    }
    
    /// Formats the descriptions of available tools.
    ///
    /// - Parameter tools: An array of available tools.
    /// - Returns: A formatted string containing tool descriptions.
    static func formatToolDescriptions(_ tools: [any Tool]) -> String {
        tools
            .map { tool in
                """
                **\(tool.name)**
                \(tool.description)
                """
            }
            .joined(separator: "\n\n")
    }
}
