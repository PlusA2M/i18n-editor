//
//  MessageFormatValidator.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation

/// Validates and supports inlang message format schema in locale files
class MessageFormatValidator: ObservableObject {
    @Published var isValidating = false
    @Published var validationResults: [MessageValidationResult] = []
    
    // MARK: - Message Format Validation
    
    /// Validate message format according to inlang schema
    func validateMessage(_ message: String, key: String, locale: String) -> MessageValidationResult {
        var issues: [MessageFormatIssue] = []
        var placeholders: [MessagePlaceholder] = []
        var messageType: MessageType = .simple
        
        // Detect message type
        messageType = detectMessageType(message)
        
        // Extract and validate placeholders
        placeholders = extractPlaceholders(from: message)
        
        // Validate placeholder syntax
        for placeholder in placeholders {
            let placeholderIssues = validatePlaceholder(placeholder, in: message)
            issues.append(contentsOf: placeholderIssues)
        }
        
        // Validate message structure
        let structureIssues = validateMessageStructure(message, type: messageType)
        issues.append(contentsOf: structureIssues)
        
        // Validate content
        let contentIssues = validateMessageContent(message)
        issues.append(contentsOf: contentIssues)
        
        return MessageValidationResult(
            key: key,
            locale: locale,
            message: message,
            type: messageType,
            placeholders: placeholders,
            issues: issues,
            isValid: issues.filter { $0.severity == .error }.isEmpty
        )
    }
    
    /// Validate multiple messages
    func validateMessages(_ messages: [String: String], locale: String) -> [MessageValidationResult] {
        isValidating = true
        
        defer { isValidating = false }
        
        var results: [MessageValidationResult] = []
        
        for (key, message) in messages {
            let result = validateMessage(message, key: key, locale: locale)
            results.append(result)
        }
        
        validationResults = results
        return results
    }
    
    // MARK: - Message Type Detection
    
    private func detectMessageType(_ message: String) -> MessageType {
        // Check for ICU MessageFormat patterns
        if message.contains("{") && message.contains("}") {
            if message.contains("select") || message.contains("plural") {
                return .icu
            } else {
                return .interpolation
            }
        }
        
        // Check for simple variable patterns
        if message.contains("{{") && message.contains("}}") {
            return .template
        }
        
        // Check for function calls
        if message.contains("@:") {
            return .linked
        }
        
        return .simple
    }
    
    // MARK: - Placeholder Extraction and Validation
    
    private func extractPlaceholders(from message: String) -> [MessagePlaceholder] {
        var placeholders: [MessagePlaceholder] = []
        
        // Extract ICU MessageFormat placeholders: {variable}
        let icuPattern = #"\{([^}]+)\}"#
        if let icuRegex = try? NSRegularExpression(pattern: icuPattern) {
            let matches = icuRegex.matches(in: message, range: NSRange(message.startIndex..., in: message))
            
            for match in matches {
                if match.numberOfRanges > 1 {
                    let range = match.range(at: 1)
                    let placeholder = String(message[Range(range, in: message)!])
                    let fullRange = match.range(at: 0)
                    
                    let placeholderObj = MessagePlaceholder(
                        name: placeholder,
                        type: .icu,
                        range: fullRange,
                        content: placeholder
                    )
                    
                    placeholders.append(placeholderObj)
                }
            }
        }
        
        // Extract template placeholders: {{variable}}
        let templatePattern = #"\{\{([^}]+)\}\}"#
        if let templateRegex = try? NSRegularExpression(pattern: templatePattern) {
            let matches = templateRegex.matches(in: message, range: NSRange(message.startIndex..., in: message))
            
            for match in matches {
                if match.numberOfRanges > 1 {
                    let range = match.range(at: 1)
                    let placeholder = String(message[Range(range, in: message)!])
                    let fullRange = match.range(at: 0)
                    
                    let placeholderObj = MessagePlaceholder(
                        name: placeholder,
                        type: .template,
                        range: fullRange,
                        content: placeholder
                    )
                    
                    placeholders.append(placeholderObj)
                }
            }
        }
        
        // Extract linked messages: @:key
        let linkedPattern = #"@:([a-zA-Z0-9_.]+)"#
        if let linkedRegex = try? NSRegularExpression(pattern: linkedPattern) {
            let matches = linkedRegex.matches(in: message, range: NSRange(message.startIndex..., in: message))
            
            for match in matches {
                if match.numberOfRanges > 1 {
                    let range = match.range(at: 1)
                    let placeholder = String(message[Range(range, in: message)!])
                    let fullRange = match.range(at: 0)
                    
                    let placeholderObj = MessagePlaceholder(
                        name: placeholder,
                        type: .linked,
                        range: fullRange,
                        content: placeholder
                    )
                    
                    placeholders.append(placeholderObj)
                }
            }
        }
        
        return placeholders
    }
    
    private func validatePlaceholder(_ placeholder: MessagePlaceholder, in message: String) -> [MessageFormatIssue] {
        var issues: [MessageFormatIssue] = []
        
        switch placeholder.type {
        case .icu:
            issues.append(contentsOf: validateICUPlaceholder(placeholder))
        case .template:
            issues.append(contentsOf: validateTemplatePlaceholder(placeholder))
        case .linked:
            issues.append(contentsOf: validateLinkedPlaceholder(placeholder))
        }
        
        return issues
    }
    
    private func validateICUPlaceholder(_ placeholder: MessagePlaceholder) -> [MessageFormatIssue] {
        var issues: [MessageFormatIssue] = []
        
        let content = placeholder.content
        
        // Check for valid variable name
        if content.isEmpty {
            issues.append(MessageFormatIssue(
                type: .error,
                severity: .error,
                message: "Empty placeholder",
                range: placeholder.range,
                suggestion: "Provide a variable name"
            ))
        }
        
        // Check for ICU MessageFormat syntax
        if content.contains(",") {
            let parts = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            if parts.count >= 2 {
                let variableName = parts[0]
                let formatType = parts[1]
                
                // Validate variable name
                if !isValidVariableName(variableName) {
                    issues.append(MessageFormatIssue(
                        type: .error,
                        severity: .error,
                        message: "Invalid variable name: \(variableName)",
                        range: placeholder.range,
                        suggestion: "Use alphanumeric characters and underscores only"
                    ))
                }
                
                // Validate format type
                let validTypes = ["number", "date", "time", "select", "plural", "selectordinal"]
                if !validTypes.contains(formatType) {
                    issues.append(MessageFormatIssue(
                        type: .warning,
                        severity: .warning,
                        message: "Unknown format type: \(formatType)",
                        range: placeholder.range,
                        suggestion: "Use one of: \(validTypes.joined(separator: ", "))"
                    ))
                }
                
                // Validate plural/select syntax
                if formatType == "plural" || formatType == "select" {
                    issues.append(contentsOf: validatePluralSelectSyntax(content, placeholder: placeholder))
                }
            }
        } else {
            // Simple variable
            if !isValidVariableName(content) {
                issues.append(MessageFormatIssue(
                    type: .error,
                    severity: .error,
                    message: "Invalid variable name: \(content)",
                    range: placeholder.range,
                    suggestion: "Use alphanumeric characters and underscores only"
                ))
            }
        }
        
        return issues
    }
    
    private func validateTemplatePlaceholder(_ placeholder: MessagePlaceholder) -> [MessageFormatIssue] {
        var issues: [MessageFormatIssue] = []
        
        if !isValidVariableName(placeholder.content) {
            issues.append(MessageFormatIssue(
                type: .error,
                severity: .error,
                message: "Invalid template variable name: \(placeholder.content)",
                range: placeholder.range,
                suggestion: "Use alphanumeric characters and underscores only"
            ))
        }
        
        return issues
    }
    
    private func validateLinkedPlaceholder(_ placeholder: MessagePlaceholder) -> [MessageFormatIssue] {
        var issues: [MessageFormatIssue] = []
        
        if !isValidKeyName(placeholder.content) {
            issues.append(MessageFormatIssue(
                type: .error,
                severity: .error,
                message: "Invalid linked message key: \(placeholder.content)",
                range: placeholder.range,
                suggestion: "Use valid key format (alphanumeric, dots, underscores)"
            ))
        }
        
        return issues
    }
    
    private func validatePluralSelectSyntax(_ content: String, placeholder: MessagePlaceholder) -> [MessageFormatIssue] {
        var issues: [MessageFormatIssue] = []
        
        // Basic validation for plural/select syntax
        // This is a simplified version - full ICU MessageFormat parsing would be more complex
        
        if !content.contains("other") {
            issues.append(MessageFormatIssue(
                type: .error,
                severity: .error,
                message: "Plural/select format must include 'other' case",
                range: placeholder.range,
                suggestion: "Add 'other {default message}' case"
            ))
        }
        
        return issues
    }
    
    // MARK: - Message Structure Validation
    
    private func validateMessageStructure(_ message: String, type: MessageType) -> [MessageFormatIssue] {
        var issues: [MessageFormatIssue] = []
        
        // Check for balanced braces
        let openBraces = message.filter { $0 == "{" }.count
        let closeBraces = message.filter { $0 == "}" }.count
        
        if openBraces != closeBraces {
            issues.append(MessageFormatIssue(
                type: .error,
                severity: .error,
                message: "Unbalanced braces in message",
                range: NSRange(location: 0, length: message.count),
                suggestion: "Ensure all opening braces have matching closing braces"
            ))
        }
        
        // Check for nested braces (not allowed in simple interpolation)
        if type == .interpolation {
            var braceDepth = 0
            var maxDepth = 0
            
            for char in message {
                if char == "{" {
                    braceDepth += 1
                    maxDepth = max(maxDepth, braceDepth)
                } else if char == "}" {
                    braceDepth -= 1
                }
            }
            
            if maxDepth > 1 {
                issues.append(MessageFormatIssue(
                    type: .warning,
                    severity: .warning,
                    message: "Nested braces detected",
                    range: NSRange(location: 0, length: message.count),
                    suggestion: "Consider using ICU MessageFormat for complex structures"
                ))
            }
        }
        
        return issues
    }
    
    // MARK: - Content Validation
    
    private func validateMessageContent(_ message: String) -> [MessageFormatIssue] {
        var issues: [MessageFormatIssue] = []
        
        // Check for common issues
        
        // Empty message
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(MessageFormatIssue(
                type: .warning,
                severity: .warning,
                message: "Message is empty",
                range: NSRange(location: 0, length: message.count),
                suggestion: "Provide translation content"
            ))
        }
        
        // Very long message
        if message.count > 1000 {
            issues.append(MessageFormatIssue(
                type: .info,
                severity: .info,
                message: "Message is very long (\(message.count) characters)",
                range: NSRange(location: 0, length: message.count),
                suggestion: "Consider breaking into smaller messages"
            ))
        }
        
        // Leading/trailing whitespace
        if message != message.trimmingCharacters(in: .whitespacesAndNewlines) {
            issues.append(MessageFormatIssue(
                type: .info,
                severity: .info,
                message: "Message has leading or trailing whitespace",
                range: NSRange(location: 0, length: message.count),
                suggestion: "Remove unnecessary whitespace"
            ))
        }
        
        // Multiple consecutive spaces
        if message.contains("  ") {
            issues.append(MessageFormatIssue(
                type: .info,
                severity: .info,
                message: "Message contains multiple consecutive spaces",
                range: NSRange(location: 0, length: message.count),
                suggestion: "Use single spaces between words"
            ))
        }
        
        return issues
    }
    
    // MARK: - Utility Methods
    
    private func isValidVariableName(_ name: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_]*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: name.count)
        return regex?.firstMatch(in: name, options: [], range: range) != nil
    }
    
    private func isValidKeyName(_ name: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_.]*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: name.count)
        return regex?.firstMatch(in: name, options: [], range: range) != nil
    }
    
    // MARK: - Cross-Locale Validation
    
    /// Compare placeholders across locales to ensure consistency
    func validatePlaceholderConsistency(_ messages: [String: String]) -> [CrossLocaleIssue] {
        var issues: [CrossLocaleIssue] = []
        var keyPlaceholders: [String: Set<String>] = [:]
        
        // Extract placeholders for each locale
        for (locale, message) in messages {
            let placeholders = extractPlaceholders(from: message)
            let placeholderNames = Set(placeholders.map { $0.name })
            keyPlaceholders[locale] = placeholderNames
        }
        
        // Find inconsistencies
        let allLocales = Array(keyPlaceholders.keys)
        
        for i in 0..<allLocales.count {
            for j in (i + 1)..<allLocales.count {
                let locale1 = allLocales[i]
                let locale2 = allLocales[j]
                
                let placeholders1 = keyPlaceholders[locale1] ?? []
                let placeholders2 = keyPlaceholders[locale2] ?? []
                
                let missing1 = placeholders2.subtracting(placeholders1)
                let missing2 = placeholders1.subtracting(placeholders2)
                
                if !missing1.isEmpty {
                    issues.append(CrossLocaleIssue(
                        type: .missingPlaceholders,
                        locale1: locale1,
                        locale2: locale2,
                        message: "Missing placeholders in \(locale1): \(missing1.joined(separator: ", "))",
                        affectedPlaceholders: Array(missing1)
                    ))
                }
                
                if !missing2.isEmpty {
                    issues.append(CrossLocaleIssue(
                        type: .missingPlaceholders,
                        locale1: locale2,
                        locale2: locale1,
                        message: "Missing placeholders in \(locale2): \(missing2.joined(separator: ", "))",
                        affectedPlaceholders: Array(missing2)
                    ))
                }
            }
        }
        
        return issues
    }
}

// MARK: - Supporting Types

struct MessageValidationResult: Identifiable {
    let id = UUID()
    let key: String
    let locale: String
    let message: String
    let type: MessageType
    let placeholders: [MessagePlaceholder]
    let issues: [MessageFormatIssue]
    let isValid: Bool
}

struct MessagePlaceholder: Identifiable {
    let id = UUID()
    let name: String
    let type: PlaceholderType
    let range: NSRange
    let content: String
}

struct MessageFormatIssue: Identifiable {
    let id = UUID()
    let type: IssueType
    let severity: IssueSeverity
    let message: String
    let range: NSRange
    let suggestion: String
}

struct CrossLocaleIssue: Identifiable {
    let id = UUID()
    let type: CrossLocaleIssueType
    let locale1: String
    let locale2: String
    let message: String
    let affectedPlaceholders: [String]
}

enum MessageType {
    case simple         // Plain text
    case interpolation  // Simple variable substitution
    case template       // Template variables {{var}}
    case icu           // ICU MessageFormat
    case linked        // Linked messages @:key
}

enum PlaceholderType {
    case icu       // {variable}
    case template  // {{variable}}
    case linked    // @:key
}

enum IssueType {
    case syntax
    case structure
    case content
    case placeholder
    case error
    case warning
    case info
}

enum IssueSeverity {
    case error
    case warning
    case info
}

enum CrossLocaleIssueType {
    case missingPlaceholders
    case extraPlaceholders
    case typeMismatch
}
