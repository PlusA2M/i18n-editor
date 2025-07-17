//
//  InlangConfigParser.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation

/// Parser for inlang project configuration files (project.inlang/settings.json)
class InlangConfigParser: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: InlangConfigError?

    // MARK: - Main Parsing Methods

    /// Parse inlang configuration from project directory
    func parseConfiguration(projectPath: String) -> InlangConfiguration? {
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        do {
            return try withSecurityScopedAccess(to: projectPath) { projectURL in
                let configPath = URL(fileURLWithPath: projectPath)
                    .appendingPathComponent("project.inlang")
                    .appendingPathComponent("settings.json")

                guard FileManager.default.fileExists(atPath: configPath.path) else {
                    lastError = .configFileNotFound(path: configPath.path)
                    return nil
                }

                do {
                    let data = try Data(contentsOf: configPath)
                    let config = try parseConfigurationData(data)
                    return config
                } catch let error as InlangConfigError {
                    lastError = error
                    return nil
                } catch {
                    lastError = .parsingError(message: error.localizedDescription)
                    return nil
                }
            }
        } catch {
            lastError = .parsingError(message: "Security-scoped access failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Parse configuration from JSON data
    private func parseConfigurationData(_ data: Data) throws -> InlangConfiguration {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InlangConfigError.invalidFormat(message: "Root object is not a dictionary")
        }

        // Skip $schema property - it's used for JSON schema validation and not part of configuration
        // This ensures the parser doesn't treat $schema as a configuration field

        // Parse base locale
        guard let baseLocale = json["baseLocale"] as? String else {
            throw InlangConfigError.missingRequiredField(field: "baseLocale")
        }

        // Parse locales array
        guard let localesArray = json["locales"] as? [String] else {
            throw InlangConfigError.missingRequiredField(field: "locales")
        }

        // Parse modules
        let modules = try parseModules(json["modules"] as? [[String: Any]] ?? [])

        // Extract path pattern from modules
        let pathPattern = extractPathPattern(from: modules)

        // Parse optional fields
        let sourceLanguageTag = json["sourceLanguageTag"] as? String
        let languageTags = json["languageTags"] as? [String] ?? localesArray
        let experimental = json["experimental"] as? [String: Any] ?? [:]

        return InlangConfiguration(
            baseLocale: baseLocale,
            locales: localesArray,
            sourceLanguageTag: sourceLanguageTag,
            languageTags: languageTags,
            modules: modules,
            pathPattern: pathPattern,
            experimental: experimental
        )
    }

    /// Parse modules configuration
    private func parseModules(_ modulesArray: [[String: Any]]) throws -> [InlangModule] {
        var modules: [InlangModule] = []

        for moduleData in modulesArray {
            guard let id = moduleData["id"] as? String else {
                throw InlangConfigError.invalidModuleFormat(message: "Module missing 'id' field")
            }

            let settings = moduleData["settings"] as? [String: Any] ?? [:]

            // Parse specific module types
            let moduleType = determineModuleType(from: id)
            let parsedSettings = try parseModuleSettings(settings, for: moduleType)

            let module = InlangModule(
                id: id,
                type: moduleType,
                settings: parsedSettings
            )

            modules.append(module)
        }

        return modules
    }

    /// Determine module type from ID
    private func determineModuleType(from id: String) -> InlangModuleType {
        if id.contains("messageFormat") {
            return .messageFormat
        } else if id.contains("plugin") {
            return .plugin
        } else if id.contains("lint") {
            return .lintRule
        } else {
            return .unknown
        }
    }

    /// Parse module-specific settings
    private func parseModuleSettings(_ settings: [String: Any], for type: InlangModuleType) throws -> InlangModuleSettings {
        switch type {
        case .messageFormat:
            return try parseMessageFormatSettings(settings)
        case .plugin:
            return try parsePluginSettings(settings)
        case .lintRule:
            return try parseLintRuleSettings(settings)
        case .unknown:
            return .unknown(settings)
        }
    }

    /// Parse message format module settings
    private func parseMessageFormatSettings(_ settings: [String: Any]) throws -> InlangModuleSettings {
        let pathPattern = settings["pathPattern"] as? String
        let variableReferencePattern = settings["variableReferencePattern"] as? [String: String] ?? [:]
        let messageReferenceMatchers = settings["messageReferenceMatchers"] as? [[String: Any]] ?? []

        return .messageFormat(MessageFormatSettings(
            pathPattern: pathPattern,
            variableReferencePattern: variableReferencePattern,
            messageReferenceMatchers: messageReferenceMatchers
        ))
    }

    /// Parse plugin settings
    private func parsePluginSettings(_ settings: [String: Any]) throws -> InlangModuleSettings {
        return .plugin(PluginSettings(
            configuration: settings
        ))
    }

    /// Parse lint rule settings
    private func parseLintRuleSettings(_ settings: [String: Any]) throws -> InlangModuleSettings {
        let level = settings["level"] as? String ?? "warning"
        let enabled = settings["enabled"] as? Bool ?? true

        return .lintRule(LintRuleSettings(
            level: level,
            enabled: enabled,
            configuration: settings
        ))
    }

    /// Extract path pattern from modules
    private func extractPathPattern(from modules: [InlangModule]) -> String? {
        for module in modules {
            if case .messageFormat(let settings) = module.settings {
                return settings.pathPattern
            }
        }
        return nil
    }

    // MARK: - Configuration Validation

    /// Validate parsed configuration
    func validateConfiguration(_ config: InlangConfiguration) -> [InlangConfigValidationIssue] {
        var issues: [InlangConfigValidationIssue] = []

        // Validate base locale is in locales array
        if !config.locales.contains(config.baseLocale) {
            issues.append(InlangConfigValidationIssue(
                type: .error,
                message: "Base locale '\(config.baseLocale)' is not included in locales array",
                field: "baseLocale"
            ))
        }

        // Validate locales are not empty
        if config.locales.isEmpty {
            issues.append(InlangConfigValidationIssue(
                type: .error,
                message: "Locales array cannot be empty",
                field: "locales"
            ))
        }

        // Validate locale format
        for locale in config.locales {
            if !isValidLocaleFormat(locale) {
                issues.append(InlangConfigValidationIssue(
                    type: .warning,
                    message: "Locale '\(locale)' may not follow standard format (e.g., 'en', 'en-US')",
                    field: "locales"
                ))
            }
        }

        // Validate path pattern
        if let pathPattern = config.pathPattern {
            if !pathPattern.contains("{locale}") {
                issues.append(InlangConfigValidationIssue(
                    type: .error,
                    message: "Path pattern must contain '{locale}' placeholder",
                    field: "pathPattern"
                ))
            }
        } else {
            issues.append(InlangConfigValidationIssue(
                type: .warning,
                message: "No path pattern found in modules. Default pattern will be used.",
                field: "modules"
            ))
        }

        // Validate modules
        if config.modules.isEmpty {
            issues.append(InlangConfigValidationIssue(
                type: .warning,
                message: "No modules configured. Some functionality may be limited.",
                field: "modules"
            ))
        }

        return issues
    }

    /// Check if locale format is valid
    private func isValidLocaleFormat(_ locale: String) -> Bool {
        // Basic validation for locale format (language-country)
        let pattern = #"^[a-z]{2}(-[A-Z]{2})?$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: locale.count)
        return regex?.firstMatch(in: locale, options: [], range: range) != nil
    }

    // MARK: - Configuration Generation

    /// Generate default configuration for a project
    func generateDefaultConfiguration(baseLocale: String = "en", locales: [String] = ["en"]) -> InlangConfiguration {
        let messageFormatModule = InlangModule(
            id: "plugin.inlang.messageFormat",
            type: .messageFormat,
            settings: .messageFormat(MessageFormatSettings(
                pathPattern: "./messages/{locale}.json",
                variableReferencePattern: [:],
                messageReferenceMatchers: []
            ))
        )

        return InlangConfiguration(
            baseLocale: baseLocale,
            locales: locales,
            sourceLanguageTag: baseLocale,
            languageTags: locales,
            modules: [messageFormatModule],
            pathPattern: "./messages/{locale}.json",
            experimental: [:]
        )
    }

    /// Save configuration to file
    func saveConfiguration(_ config: InlangConfiguration, to projectPath: String) throws {
        let configDir = URL(fileURLWithPath: projectPath).appendingPathComponent("project.inlang")
        let configFile = configDir.appendingPathComponent("settings.json")

        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Convert configuration to JSON
        let jsonData = try serializeConfiguration(config)

        // Write to file
        try jsonData.write(to: configFile)
    }

    // MARK: - Security-Scoped Access Helper

    /// Helper method for security-scoped access to project files
    private func withSecurityScopedAccess<T>(to projectPath: String, operation: (URL) throws -> T) throws -> T {
        // Try to restore security-scoped access from bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(projectPath)") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

                if isStale {
                    throw NSError(domain: "InlangConfigParserError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project access permissions have expired. Please reopen the project folder."])
                }

                // Start accessing the security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "InlangConfigParserError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to access project directory. Please reopen the project folder."])
                }

                defer {
                    url.stopAccessingSecurityScopedResource()
                }

                return try operation(url)

            } catch {
                // If bookmark fails, fall back to direct access (might work in some cases)
                print("Security-scoped bookmark failed: \(error). Attempting direct access...")
                let url = URL(fileURLWithPath: projectPath)
                return try operation(url)
            }
        } else {
            // No bookmark available, try direct access
            print("No security-scoped bookmark found for project: \(projectPath). Attempting direct access...")
            let url = URL(fileURLWithPath: projectPath)
            return try operation(url)
        }
    }

    /// Update configuration incrementally, preserving existing custom settings
    func updateConfigurationIncrementally(_ config: InlangConfiguration, to projectPath: String) throws {
        try withSecurityScopedAccess(to: projectPath) { projectURL in
            let configDir = URL(fileURLWithPath: projectPath).appendingPathComponent("project.inlang")
            let configFile = configDir.appendingPathComponent("settings.json")

            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            var existingJson: [String: Any] = [:]

            // Load existing configuration if it exists
            if FileManager.default.fileExists(atPath: configFile.path) {
                let existingData = try Data(contentsOf: configFile)
                existingJson = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] ?? [:]
            }

        // Update only the specific fields that changed, preserving all other settings
        existingJson["baseLocale"] = config.baseLocale
        existingJson["locales"] = config.locales

        // Update optional fields only if they have values
        if let sourceLanguageTag = config.sourceLanguageTag {
            existingJson["sourceLanguageTag"] = sourceLanguageTag
        }

        if config.languageTags != config.locales {
            existingJson["languageTags"] = config.languageTags
        }

        // Preserve $schema if it exists
        if existingJson["$schema"] == nil {
            existingJson["$schema"] = "https://inlang.com/schema/project-settings"
        }

        // Update modules while preserving existing module configurations
        var modulesArray: [[String: Any]] = []

        // Get existing modules to preserve their structure
        let existingModules = existingJson["modules"] as? [[String: Any]] ?? []
        let existingModulesById: [String: [String: Any]] = Dictionary(uniqueKeysWithValues: existingModules.compactMap { module in
            guard let id = module["id"] as? String else { return nil }
            return (id, module)
        })

        for module in config.modules {
            var moduleJson: [String: Any] = ["id": module.id]

            // Start with existing module data if available
            if let existingModule = existingModulesById[module.id] {
                moduleJson = existingModule
            }

            switch module.settings {
            case .messageFormat(let settings):
                var settingsJson: [String: Any] = [:]

                // Preserve existing plugin settings if they exist
                if let existingSettings = moduleJson["plugin.inlang.messageFormat"] as? [String: Any] {
                    settingsJson = existingSettings
                }

                // Update only the pathPattern, preserve everything else
                if let pathPattern = settings.pathPattern {
                    settingsJson["pathPattern"] = pathPattern
                }
                if !settings.variableReferencePattern.isEmpty {
                    settingsJson["variableReferencePattern"] = settings.variableReferencePattern
                }
                if !settings.messageReferenceMatchers.isEmpty {
                    settingsJson["messageReferenceMatchers"] = settings.messageReferenceMatchers
                }

                if !settingsJson.isEmpty {
                    moduleJson["plugin.inlang.messageFormat"] = settingsJson
                }

            case .plugin(let settings):
                // Preserve existing plugin configuration and merge with new settings
                if let existingSettings = moduleJson["settings"] as? [String: Any] {
                    var mergedSettings = existingSettings
                    for (key, value) in settings.configuration {
                        mergedSettings[key] = value
                    }
                    moduleJson["settings"] = mergedSettings
                } else if !settings.configuration.isEmpty {
                    moduleJson["settings"] = settings.configuration
                }

            case .lintRule(let settings):
                var settingsJson: [String: Any] = [
                    "level": settings.level,
                    "enabled": settings.enabled
                ]

                // Preserve existing lint rule settings
                if let existingSettings = moduleJson["settings"] as? [String: Any] {
                    for (key, value) in existingSettings {
                        if key != "level" && key != "enabled" {
                            settingsJson[key] = value
                        }
                    }
                }

                for (key, value) in settings.configuration {
                    if key != "level" && key != "enabled" {
                        settingsJson[key] = value
                    }
                }
                moduleJson["settings"] = settingsJson

            case .unknown(let settings):
                // Preserve existing unknown settings and merge with new ones
                if let existingSettings = moduleJson["settings"] as? [String: Any] {
                    var mergedSettings = existingSettings
                    for (key, value) in settings {
                        mergedSettings[key] = value
                    }
                    moduleJson["settings"] = mergedSettings
                } else if !settings.isEmpty {
                    moduleJson["settings"] = settings
                }
            }

            modulesArray.append(moduleJson)
        }

        if !modulesArray.isEmpty {
            existingJson["modules"] = modulesArray
        }

        // Preserve experimental settings if they exist
        if !config.experimental.isEmpty {
            existingJson["experimental"] = config.experimental
        }

            // Write updated configuration back to file
            let jsonData = try JSONSerialization.data(withJSONObject: existingJson, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try jsonData.write(to: configFile)
        }
    }

    /// Serialize configuration to JSON data
    private func serializeConfiguration(_ config: InlangConfiguration) throws -> Data {
        var json: [String: Any] = [
            "baseLocale": config.baseLocale,
            "locales": config.locales
        ]

        if let sourceLanguageTag = config.sourceLanguageTag {
            json["sourceLanguageTag"] = sourceLanguageTag
        }

        if config.languageTags != config.locales {
            json["languageTags"] = config.languageTags
        }

        // Serialize modules
        var modulesArray: [[String: Any]] = []
        for module in config.modules {
            var moduleJson: [String: Any] = ["id": module.id]

            switch module.settings {
            case .messageFormat(let settings):
                var settingsJson: [String: Any] = [:]
                if let pathPattern = settings.pathPattern {
                    settingsJson["pathPattern"] = pathPattern
                }
                if !settings.variableReferencePattern.isEmpty {
                    settingsJson["variableReferencePattern"] = settings.variableReferencePattern
                }
                if !settings.messageReferenceMatchers.isEmpty {
                    settingsJson["messageReferenceMatchers"] = settings.messageReferenceMatchers
                }
                if !settingsJson.isEmpty {
                    moduleJson["settings"] = settingsJson
                }

            case .plugin(let settings):
                if !settings.configuration.isEmpty {
                    moduleJson["settings"] = settings.configuration
                }

            case .lintRule(let settings):
                var settingsJson: [String: Any] = [
                    "level": settings.level,
                    "enabled": settings.enabled
                ]
                for (key, value) in settings.configuration {
                    if key != "level" && key != "enabled" {
                        settingsJson[key] = value
                    }
                }
                moduleJson["settings"] = settingsJson

            case .unknown(let settings):
                if !settings.isEmpty {
                    moduleJson["settings"] = settings
                }
            }

            modulesArray.append(moduleJson)
        }

        if !modulesArray.isEmpty {
            json["modules"] = modulesArray
        }

        if !config.experimental.isEmpty {
            json["experimental"] = config.experimental
        }

        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

// MARK: - Supporting Types

struct InlangConfiguration {
    let baseLocale: String
    let locales: [String]
    let sourceLanguageTag: String?
    let languageTags: [String]
    let modules: [InlangModule]
    let pathPattern: String?
    let experimental: [String: Any]
}

struct InlangModule {
    let id: String
    let type: InlangModuleType
    let settings: InlangModuleSettings
}

enum InlangModuleType {
    case messageFormat
    case plugin
    case lintRule
    case unknown
}

enum InlangModuleSettings {
    case messageFormat(MessageFormatSettings)
    case plugin(PluginSettings)
    case lintRule(LintRuleSettings)
    case unknown([String: Any])
}

struct MessageFormatSettings {
    let pathPattern: String?
    let variableReferencePattern: [String: String]
    let messageReferenceMatchers: [[String: Any]]
}

struct PluginSettings {
    let configuration: [String: Any]
}

struct LintRuleSettings {
    let level: String
    let enabled: Bool
    let configuration: [String: Any]
}

struct InlangConfigValidationIssue {
    let type: InlangConfigValidationIssueType
    let message: String
    let field: String
}

enum InlangConfigValidationIssueType {
    case error
    case warning
    case info
}

enum InlangConfigError: Error, LocalizedError {
    case configFileNotFound(path: String)
    case invalidFormat(message: String)
    case missingRequiredField(field: String)
    case invalidModuleFormat(message: String)
    case parsingError(message: String)

    var errorDescription: String? {
        switch self {
        case .configFileNotFound(let path):
            return "Configuration file not found at: \(path)"
        case .invalidFormat(let message):
            return "Invalid configuration format: \(message)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidModuleFormat(let message):
            return "Invalid module format: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
}
