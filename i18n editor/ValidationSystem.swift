//
//  ValidationSystem.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import SwiftUI

/// Comprehensive validation system for translations, keys, and project integrity
class ValidationSystem: ObservableObject {
    @Published var isValidating = false
    @Published var validationResults: [ValidationResult] = []
    @Published var validationSummary: ValidationSummary?
    @Published var autoValidationEnabled = true
    
    private let messageValidator = MessageFormatValidator()
    private let dataManager = DataManager.shared
    private var validationTimer: Timer?
    
    // MARK: - Main Validation Methods
    
    /// Validate entire project
    func validateProject(_ project: Project) async -> ProjectValidationResult {
        await MainActor.run {
            isValidating = true
            validationResults = []
        }
        
        defer {
            Task { @MainActor in
                isValidating = false
            }
        }
        
        var allResults: [ValidationResult] = []
        
        // Validate project structure
        let structureResults = await validateProjectStructure(project)
        allResults.append(contentsOf: structureResults)
        
        // Validate i18n keys
        let keyResults = await validateI18nKeys(project)
        allResults.append(contentsOf: keyResults)
        
        // Validate translations
        let translationResults = await validateTranslations(project)
        allResults.append(contentsOf: translationResults)
        
        // Validate locale files
        let localeResults = await validateLocaleFiles(project)
        allResults.append(contentsOf: localeResults)
        
        // Cross-validation checks
        let crossResults = await performCrossValidation(project)
        allResults.append(contentsOf: crossResults)
        
        await MainActor.run {
            validationResults = allResults
            validationSummary = createValidationSummary(allResults)
        }
        
        return ProjectValidationResult(
            results: allResults,
            summary: validationSummary!,
            validatedAt: Date()
        )
    }
    
    /// Validate project structure and configuration
    private func validateProjectStructure(_ project: Project) async -> [ValidationResult] {
        var results: [ValidationResult] = []
        
        // Check project path exists
        if let path = project.path {
            if !FileManager.default.fileExists(atPath: path) {
                results.append(ValidationResult(
                    type: .error,
                    category: .projectStructure,
                    title: "Project path not found",
                    message: "Project directory does not exist: \(path)",
                    suggestion: "Verify the project path is correct",
                    affectedItem: .project(project),
                    canAutoFix: false
                ))
            }
        }
        
        // Check for inlang configuration
        if project.inlangConfigPath == nil {
            results.append(ValidationResult(
                type: .warning,
                category: .projectStructure,
                title: "No inlang configuration",
                message: "Project does not have an inlang configuration file",
                suggestion: "Create project.inlang/settings.json for better integration",
                affectedItem: .project(project),
                canAutoFix: true
            ))
        }
        
        // Validate locales configuration
        if project.allLocales.isEmpty {
            results.append(ValidationResult(
                type: .error,
                category: .projectStructure,
                title: "No locales configured",
                message: "Project must have at least one locale configured",
                suggestion: "Add locales to project configuration",
                affectedItem: .project(project),
                canAutoFix: false
            ))
        }
        
        // Check base locale is in locales list
        if let baseLocale = project.baseLocale, !project.allLocales.contains(baseLocale) {
            results.append(ValidationResult(
                type: .error,
                category: .projectStructure,
                title: "Invalid base locale",
                message: "Base locale '\(baseLocale)' is not in the locales list",
                suggestion: "Add base locale to locales list or change base locale",
                affectedItem: .project(project),
                canAutoFix: true
            ))
        }
        
        return results
    }
    
    /// Validate i18n keys
    private func validateI18nKeys(_ project: Project) async -> [ValidationResult] {
        var results: [ValidationResult] = []
        let keys = dataManager.getI18nKeys(for: project)
        
        for key in keys {
            // Check for empty key names
            if key.key?.isEmpty == true {
                results.append(ValidationResult(
                    type: .error,
                    category: .keyStructure,
                    title: "Empty key name",
                    message: "Key has empty or null name",
                    suggestion: "Provide a valid key name",
                    affectedItem: .key(key),
                    canAutoFix: false
                ))
                continue
            }
            
            // Check key naming conventions
            if let keyName = key.key {
                if !isValidKeyName(keyName) {
                    results.append(ValidationResult(
                        type: .warning,
                        category: .keyStructure,
                        title: "Invalid key format",
                        message: "Key '\(keyName)' doesn't follow naming conventions",
                        suggestion: "Use alphanumeric characters, dots, and underscores only",
                        affectedItem: .key(key),
                        canAutoFix: false
                    ))
                }
                
                // Check for very long keys
                if keyName.count > 100 {
                    results.append(ValidationResult(
                        type: .info,
                        category: .keyStructure,
                        title: "Very long key name",
                        message: "Key '\(keyName)' is very long (\(keyName.count) characters)",
                        suggestion: "Consider using shorter, more descriptive key names",
                        affectedItem: .key(key),
                        canAutoFix: false
                    ))
                }
            }
            
            // Check for unused keys
            if !key.isUsedInFiles {
                results.append(ValidationResult(
                    type: .warning,
                    category: .keyUsage,
                    title: "Unused key",
                    message: "Key '\(key.key ?? "")' is not used in any files",
                    suggestion: "Remove unused key or add usage in code",
                    affectedItem: .key(key),
                    canAutoFix: true
                ))
            }
            
            // Check for missing translations
            if key.hasMissingTranslations {
                let missingLocales = project.allLocales.filter { locale in
                    !key.allTranslations.contains { $0.locale == locale && !($0.value?.isEmpty ?? true) }
                }
                
                results.append(ValidationResult(
                    type: .warning,
                    category: .translation,
                    title: "Missing translations",
                    message: "Key '\(key.key ?? "")' is missing translations for: \(missingLocales.joined(separator: ", "))",
                    suggestion: "Add translations for missing locales",
                    affectedItem: .key(key),
                    canAutoFix: false
                ))
            }
        }
        
        return results
    }
    
    /// Validate translations
    private func validateTranslations(_ project: Project) async -> [ValidationResult] {
        var results: [ValidationResult] = []
        let translations = project.translations?.allObjects as? [Translation] ?? []
        
        for translation in translations {
            guard let key = translation.i18nKey,
                  let locale = translation.locale else { continue }
            
            // Validate message format
            if let value = translation.effectiveValue, !value.isEmpty {
                let messageResult = messageValidator.validateMessage(value, key: key.key ?? "", locale: locale)
                
                for issue in messageResult.issues {
                    let severity: ValidationSeverity = issue.severity == .error ? .error : .warning
                    
                    results.append(ValidationResult(
                        type: severity,
                        category: .messageFormat,
                        title: "Message format issue",
                        message: issue.message,
                        suggestion: issue.suggestion,
                        affectedItem: .translation(translation),
                        canAutoFix: false
                    ))
                }
            }
            
            // Check for empty translations
            if translation.effectiveValue?.isEmpty == true {
                results.append(ValidationResult(
                    type: .info,
                    category: .translation,
                    title: "Empty translation",
                    message: "Translation for '\(key.key ?? "")' in '\(locale)' is empty",
                    suggestion: "Provide translation content",
                    affectedItem: .translation(translation),
                    canAutoFix: false
                ))
            }
            
            // Check for very long translations
            if let value = translation.effectiveValue, value.count > 1000 {
                results.append(ValidationResult(
                    type: .info,
                    category: .translation,
                    title: "Very long translation",
                    message: "Translation is very long (\(value.count) characters)",
                    suggestion: "Consider breaking into smaller parts",
                    affectedItem: .translation(translation),
                    canAutoFix: false
                ))
            }
            
            // Check for draft translations that are old
            if translation.isDraft, let lastModified = translation.lastModified {
                let daysSinceModified = Date().timeIntervalSince(lastModified) / (24 * 60 * 60)
                if daysSinceModified > 7 {
                    results.append(ValidationResult(
                        type: .info,
                        category: .translation,
                        title: "Old draft translation",
                        message: "Draft translation has been unchanged for \(Int(daysSinceModified)) days",
                        suggestion: "Review and commit or discard the draft",
                        affectedItem: .translation(translation),
                        canAutoFix: false
                    ))
                }
            }
        }
        
        return results
    }
    
    /// Validate locale files
    private func validateLocaleFiles(_ project: Project) async -> [ValidationResult] {
        var results: [ValidationResult] = []
        let localeManager = LocaleFileManager()
        
        guard let config = try? InlangConfigParser().parseConfiguration(projectPath: project.path ?? "") else {
            return results
        }
        
        let localeFiles = localeManager.discoverLocaleFiles(config: config, projectPath: project.path ?? "")
        
        for localeFile in localeFiles {
            // Check if file exists
            if !localeFile.exists {
                results.append(ValidationResult(
                    type: .warning,
                    category: .localeFile,
                    title: "Missing locale file",
                    message: "Locale file for '\(localeFile.locale)' does not exist",
                    suggestion: "Create the locale file: \(localeFile.relativePath)",
                    affectedItem: .localeFile(localeFile.locale),
                    canAutoFix: true
                ))
                continue
            }
            
            // Validate file structure
            let validationIssues = localeManager.validateLocaleFile(localeFile)
            
            for issue in validationIssues {
                let severity: ValidationSeverity = issue.type == .error ? .error : .warning
                
                results.append(ValidationResult(
                    type: severity,
                    category: .localeFile,
                    title: "Locale file issue",
                    message: issue.message,
                    suggestion: issue.suggestion,
                    affectedItem: .localeFile(localeFile.locale),
                    canAutoFix: false
                ))
            }
        }
        
        return results
    }
    
    /// Perform cross-validation checks
    private func performCrossValidation(_ project: Project) async -> [ValidationResult] {
        var results: [ValidationResult] = []
        
        // Check for placeholder consistency across locales
        let keys = dataManager.getI18nKeys(for: project)
        
        for key in keys {
            let translations = key.allTranslations
            let translationsByLocale = Dictionary(grouping: translations) { $0.locale ?? "" }
            
            // Get all translation values
            var messagesByLocale: [String: String] = [:]
            for (locale, localeTranslations) in translationsByLocale {
                if let translation = localeTranslations.first,
                   let value = translation.effectiveValue, !value.isEmpty {
                    messagesByLocale[locale] = value
                }
            }
            
            // Validate placeholder consistency
            let crossLocaleIssues = messageValidator.validatePlaceholderConsistency(messagesByLocale)
            
            for issue in crossLocaleIssues {
                results.append(ValidationResult(
                    type: .warning,
                    category: .crossLocale,
                    title: "Placeholder inconsistency",
                    message: issue.message,
                    suggestion: "Ensure all locales have the same placeholders",
                    affectedItem: .key(key),
                    canAutoFix: false
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Auto-Fix Functionality
    
    func autoFixIssue(_ result: ValidationResult) async -> Bool {
        guard result.canAutoFix else { return false }
        
        switch result.category {
        case .projectStructure:
            return await autoFixProjectStructure(result)
        case .keyStructure:
            return await autoFixKeyStructure(result)
        case .keyUsage:
            return await autoFixKeyUsage(result)
        case .localeFile:
            return await autoFixLocaleFile(result)
        default:
            return false
        }
    }
    
    private func autoFixProjectStructure(_ result: ValidationResult) async -> Bool {
        // Auto-fix project structure issues
        switch result.title {
        case "No inlang configuration":
            // Create default inlang configuration
            return await createDefaultInlangConfig(result)
        case "Invalid base locale":
            // Fix base locale configuration
            return await fixBaseLocaleConfig(result)
        default:
            return false
        }
    }
    
    private func autoFixKeyStructure(_ result: ValidationResult) async -> Bool {
        // Auto-fix key structure issues
        return false // Most key issues require manual intervention
    }
    
    private func autoFixKeyUsage(_ result: ValidationResult) async -> Bool {
        // Auto-fix key usage issues
        if result.title == "Unused key" {
            // Remove unused key
            return await removeUnusedKey(result)
        }
        return false
    }
    
    private func autoFixLocaleFile(_ result: ValidationResult) async -> Bool {
        // Auto-fix locale file issues
        if result.title == "Missing locale file" {
            // Create empty locale file
            return await createEmptyLocaleFile(result)
        }
        return false
    }
    
    // MARK: - Auto-Fix Implementations
    
    private func createDefaultInlangConfig(_ result: ValidationResult) async -> Bool {
        guard case .project(let project) = result.affectedItem,
              let projectPath = project.path else { return false }
        
        let parser = InlangConfigParser()
        let defaultConfig = parser.generateDefaultConfiguration(
            baseLocale: project.baseLocale ?? "en",
            locales: project.allLocales.isEmpty ? ["en"] : project.allLocales
        )
        
        do {
            try parser.saveConfiguration(defaultConfig, to: projectPath)
            return true
        } catch {
            return false
        }
    }
    
    private func fixBaseLocaleConfig(_ result: ValidationResult) async -> Bool {
        guard case .project(let project) = result.affectedItem else { return false }
        
        // Set base locale to first available locale
        if let firstLocale = project.allLocales.first {
            project.baseLocale = firstLocale
            try? dataManager.viewContext.save()
            return true
        }
        
        return false
    }
    
    private func removeUnusedKey(_ result: ValidationResult) async -> Bool {
        guard case .key(let key) = result.affectedItem else { return false }
        
        // Remove the key and all its translations
        dataManager.viewContext.delete(key)
        
        do {
            try dataManager.viewContext.save()
            return true
        } catch {
            return false
        }
    }
    
    private func createEmptyLocaleFile(_ result: ValidationResult) async -> Bool {
        guard case .localeFile(let locale) = result.affectedItem else { return false }
        
        // Create empty locale file structure
        let emptyContent: [String: Any] = [:]
        
        // This would need to be implemented with actual file creation
        // using LocaleFileManager
        
        return false // Placeholder implementation
    }
    
    // MARK: - Utility Methods
    
    private func isValidKeyName(_ keyName: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_.]*$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: keyName.count)
        return regex?.firstMatch(in: keyName, options: [], range: range) != nil
    }
    
    private func createValidationSummary(_ results: [ValidationResult]) -> ValidationSummary {
        let errorCount = results.filter { $0.type == .error }.count
        let warningCount = results.filter { $0.type == .warning }.count
        let infoCount = results.filter { $0.type == .info }.count
        let autoFixableCount = results.filter { $0.canAutoFix }.count
        
        let categoryCounts = Dictionary(grouping: results) { $0.category }
            .mapValues { $0.count }
        
        return ValidationSummary(
            totalIssues: results.count,
            errorCount: errorCount,
            warningCount: warningCount,
            infoCount: infoCount,
            autoFixableCount: autoFixableCount,
            categoryCounts: categoryCounts,
            validatedAt: Date()
        )
    }
    
    // MARK: - Auto-Validation
    
    func enableAutoValidation(for project: Project) {
        guard autoValidationEnabled else { return }
        
        validationTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.validateProject(project)
            }
        }
    }
    
    func disableAutoValidation() {
        validationTimer?.invalidate()
        validationTimer = nil
    }
}

// MARK: - Supporting Types

struct ValidationResult: Identifiable {
    let id = UUID()
    let type: ValidationSeverity
    let category: ValidationCategory
    let title: String
    let message: String
    let suggestion: String
    let affectedItem: ValidationAffectedItem
    let canAutoFix: Bool
    let createdAt = Date()
}

struct ProjectValidationResult {
    let results: [ValidationResult]
    let summary: ValidationSummary
    let validatedAt: Date
}

struct ValidationSummary {
    let totalIssues: Int
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int
    let autoFixableCount: Int
    let categoryCounts: [ValidationCategory: Int]
    let validatedAt: Date

    var hasErrors: Bool { errorCount > 0 }
    var hasWarnings: Bool { warningCount > 0 }
    var hasIssues: Bool { totalIssues > 0 }
}

enum ValidationSeverity {
    case error
    case warning
    case info
}

enum ValidationCategory: CaseIterable {
    case projectStructure
    case keyStructure
    case keyUsage
    case translation
    case messageFormat
    case localeFile
    case crossLocale

    var displayName: String {
        switch self {
        case .projectStructure: return "Project Structure"
        case .keyStructure: return "Key Structure"
        case .keyUsage: return "Key Usage"
        case .translation: return "Translation"
        case .messageFormat: return "Message Format"
        case .localeFile: return "Locale File"
        case .crossLocale: return "Cross-Locale"
        }
    }

    var icon: String {
        switch self {
        case .projectStructure: return "folder"
        case .keyStructure: return "key"
        case .keyUsage: return "link"
        case .translation: return "textformat"
        case .messageFormat: return "textformat.alt"
        case .localeFile: return "doc"
        case .crossLocale: return "globe"
        }
    }
}

enum ValidationAffectedItem {
    case project(Project)
    case key(I18nKey)
    case translation(Translation)
    case localeFile(String) // locale identifier
}

// MARK: - Validation UI Components

struct ValidationResultsView: View {
    let project: Project
    @StateObject private var validationSystem = ValidationSystem()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: ValidationCategory?
    @State private var showingAutoFixConfirmation = false
    @State private var autoFixTarget: ValidationResult?

    var body: some View {
        NavigationView {
            VStack {
                // Validation summary
                if let summary = validationSystem.validationSummary {
                    ValidationSummaryView(summary: summary)
                        .padding()
                }

                // Category filter
                CategoryFilterView(
                    categories: ValidationCategory.allCases,
                    selectedCategory: $selectedCategory,
                    results: validationSystem.validationResults
                )

                // Results list
                ValidationResultsList(
                    results: filteredResults,
                    onAutoFix: { result in
                        autoFixTarget = result
                        showingAutoFixConfirmation = true
                    }
                )
            }
            .navigationTitle("Validation Results")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Refresh") {
                        Task {
                            await validationSystem.validateProject(project)
                        }
                    }
                }

                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            Task {
                await validationSystem.validateProject(project)
            }
        }
        .alert("Auto-Fix Confirmation", isPresented: $showingAutoFixConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Fix") {
                if let target = autoFixTarget {
                    Task {
                        let success = await validationSystem.autoFixIssue(target)
                        if success {
                            await validationSystem.validateProject(project)
                        }
                    }
                }
            }
        } message: {
            Text("Are you sure you want to automatically fix this issue? This action cannot be undone.")
        }
    }

    private var filteredResults: [ValidationResult] {
        if let category = selectedCategory {
            return validationSystem.validationResults.filter { $0.category == category }
        }
        return validationSystem.validationResults
    }
}

struct ValidationSummaryView: View {
    let summary: ValidationSummary

    var body: some View {
        VStack(spacing: 12) {
            // Overall status
            HStack {
                statusIcon

                VStack(alignment: .leading) {
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(statusColor)

                    Text("Last validated: \(summary.validatedAt, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Issue counts
            HStack(spacing: 20) {
                IssueCountView(count: summary.errorCount, type: "Errors", color: .red)
                IssueCountView(count: summary.warningCount, type: "Warnings", color: .orange)
                IssueCountView(count: summary.infoCount, type: "Info", color: .blue)

                if summary.autoFixableCount > 0 {
                    IssueCountView(count: summary.autoFixableCount, type: "Auto-fixable", color: .green)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var statusIcon: some View {
        Group {
            if summary.hasErrors {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            } else if summary.hasWarnings {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .font(.title2)
    }

    private var statusText: String {
        if summary.hasErrors {
            return "Validation Failed"
        } else if summary.hasWarnings {
            return "Validation Passed with Warnings"
        } else {
            return "Validation Passed"
        }
    }

    private var statusColor: Color {
        if summary.hasErrors {
            return .red
        } else if summary.hasWarnings {
            return .orange
        } else {
            return .green
        }
    }
}

struct IssueCountView: View {
    let count: Int
    let type: String
    let color: Color

    var body: some View {
        VStack {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(type)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct CategoryFilterView: View {
    let categories: [ValidationCategory]
    @Binding var selectedCategory: ValidationCategory?
    let results: [ValidationResult]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All categories button
                CategoryButton(
                    title: "All",
                    icon: "list.bullet",
                    count: results.count,
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                // Individual category buttons
                ForEach(categories, id: \.self) { category in
                    let count = results.filter { $0.category == category }.count

                    if count > 0 {
                        CategoryButton(
                            title: category.displayName,
                            icon: category.icon,
                            count: count,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

struct CategoryButton: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)

                Text(title)
                    .font(.caption)

                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct ValidationResultsList: View {
    let results: [ValidationResult]
    let onAutoFix: (ValidationResult) -> Void

    var body: some View {
        List {
            ForEach(results) { result in
                ValidationResultRow(result: result, onAutoFix: onAutoFix)
            }
        }
    }
}

struct ValidationResultRow: View {
    let result: ValidationResult
    let onAutoFix: (ValidationResult) -> Void

    var body: some View {
        HStack {
            // Severity icon
            severityIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)

                Text(result.message)
                    .font(.body)
                    .foregroundColor(.secondary)

                if !result.suggestion.isEmpty {
                    Text("💡 \(result.suggestion)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            if result.canAutoFix {
                Button("Fix") {
                    onAutoFix(result)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var severityIcon: some View {
        Group {
            switch result.type {
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            case .info:
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .font(.title3)
    }
}
