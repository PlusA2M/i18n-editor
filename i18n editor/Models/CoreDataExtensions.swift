//
//  CoreDataExtensions.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import CoreData

// MARK: - Project Extensions

extension Project {
    /// Computed property for sorted i18n keys
    var sortedI18nKeys: [I18nKey] {
        let keys = i18nKeys?.allObjects as? [I18nKey] ?? []
        return keys.sorted { $0.key ?? "" < $1.key ?? "" }
    }
    
    /// Get hierarchical structure of i18n keys
    var hierarchicalKeys: [String: [I18nKey]] {
        var hierarchy: [String: [I18nKey]] = [:]
        
        for key in sortedI18nKeys {
            let keyString = key.key ?? ""
            let components = keyString.components(separatedBy: ".")
            
            if components.count > 1 {
                let namespace = components.first ?? "root"
                if hierarchy[namespace] == nil {
                    hierarchy[namespace] = []
                }
                hierarchy[namespace]?.append(key)
            } else {
                if hierarchy["root"] == nil {
                    hierarchy["root"] = []
                }
                hierarchy["root"]?.append(key)
            }
        }
        
        return hierarchy
    }
    
    /// Get all locales used in this project
    var allLocales: [String] {
        let localeSet = Set((locales ?? []).compactMap { $0 })
        return Array(localeSet).sorted()
    }
    
    /// Check if project has unsaved changes
    var hasUnsavedChanges: Bool {
        let translations = self.translations?.allObjects as? [Translation] ?? []
        return translations.contains { $0.hasUnsavedChanges == true || $0.isDraft }
    }
    
    /// Get count of draft translations
    var draftTranslationsCount: Int {
        let translations = self.translations?.allObjects as? [Translation] ?? []
        return translations.filter { $0.isDraft }.count
    }
    
    /// Get project statistics
    var statistics: ProjectStatistics {
        let keys = sortedI18nKeys
        let translations = self.translations?.allObjects as? [Translation] ?? []
        let fileUsages = self.fileUsages?.allObjects as? [FileUsage] ?? []
        
        let totalKeys = keys.count
        let totalTranslations = translations.count
        let completedTranslations = translations.filter { !($0.value?.isEmpty ?? true) }.count
        let draftTranslations = translations.filter { $0.isDraft }.count
        let filesWithUsage = Set(fileUsages.map { $0.filePath ?? "" }).count
        
        return ProjectStatistics(
            totalKeys: totalKeys,
            totalTranslations: totalTranslations,
            completedTranslations: completedTranslations,
            draftTranslations: draftTranslations,
            filesWithUsage: filesWithUsage,
            completionPercentage: totalTranslations > 0 ? Double(completedTranslations) / Double(totalTranslations) : 0.0
        )
    }
}

// MARK: - I18nKey Extensions

extension I18nKey {
    /// Get all translations for this key
    var allTranslations: [Translation] {
        let translations = self.translations?.allObjects as? [Translation] ?? []
        return translations.sorted { $0.locale ?? "" < $1.locale ?? "" }
    }
    
    /// Get translation for specific locale
    func translation(for locale: String) -> Translation? {
        return allTranslations.first { $0.locale == locale }
    }
    
    /// Get all file usages for this key
    var activeFileUsages: [FileUsage] {
        let usages = self.fileUsages?.allObjects as? [FileUsage] ?? []
        return usages.filter { $0.isActive }.sorted { $0.filePath ?? "" < $1.filePath ?? "" }
    }
    
    /// Check if key is used in any files
    var isUsedInFiles: Bool {
        return !activeFileUsages.isEmpty
    }
    
    /// Get the namespace components of the key
    var namespaceComponents: [String] {
        let keyString = key ?? ""
        let components = keyString.components(separatedBy: ".")
        return components.count > 1 ? Array(components.dropLast()) : []
    }
    
    /// Get the final component of the key (without namespace)
    var finalComponent: String {
        let keyString = key ?? ""
        let components = keyString.components(separatedBy: ".")
        return components.last ?? keyString
    }
    
    /// Check if this key has missing translations
    var hasMissingTranslations: Bool {
        guard let project = self.project else { return false }
        let projectLocales = project.allLocales
        let keyTranslations = allTranslations
        
        for locale in projectLocales {
            if !keyTranslations.contains(where: { $0.locale == locale && !($0.value?.isEmpty ?? true) }) {
                return true
            }
        }
        return false
    }
    
    /// Get completion percentage for this key
    var completionPercentage: Double {
        guard let project = self.project else { return 0.0 }
        let projectLocales = project.allLocales
        let keyTranslations = allTranslations
        
        let completedCount = projectLocales.filter { locale in
            keyTranslations.contains { $0.locale == locale && !($0.value?.isEmpty ?? true) }
        }.count
        
        return projectLocales.isEmpty ? 0.0 : Double(completedCount) / Double(projectLocales.count)
    }
}

// MARK: - Translation Extensions

extension Translation {
    /// Get the effective value (draft if available, otherwise actual value)
    var effectiveValue: String? {
        return isDraft ? draftValue : value
    }
    
    /// Check if translation is empty
    var isEmpty: Bool {
        return effectiveValue?.isEmpty ?? true
    }
    
    /// Check if translation is complete
    var isComplete: Bool {
        return !isEmpty
    }
    
    /// Get display value for UI
    var displayValue: String {
        return effectiveValue ?? ""
    }
    
    /// Validate translation value
    func validate() -> TranslationValidationResult {
        let currentValue = effectiveValue ?? ""
        
        // Basic validation rules
        var errors: [String] = []
        var warnings: [String] = []
        
        // Check for empty value
        if currentValue.isEmpty {
            warnings.append("Translation is empty")
        }
        
        // Check for placeholder consistency (basic check for {variable} patterns)
        let placeholderPattern = #"\{[^}]+\}"#
        let placeholderRegex = try? NSRegularExpression(pattern: placeholderPattern)
        let placeholderMatches = placeholderRegex?.matches(in: currentValue, range: NSRange(currentValue.startIndex..., in: currentValue)) ?? []
        
        // Check for HTML tags (might be unwanted in some contexts)
        if currentValue.contains("<") && currentValue.contains(">") {
            warnings.append("Contains HTML tags")
        }
        
        // Check for very long translations
        if currentValue.count > 500 {
            warnings.append("Translation is very long (\(currentValue.count) characters)")
        }
        
        return TranslationValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
}

// MARK: - FileUsage Extensions

extension FileUsage {
    /// Get relative file path for display
    var displayPath: String {
        guard let path = filePath, let project = self.project else { return "" }
        let projectPath = project.path ?? ""
        
        if path.hasPrefix(projectPath) {
            return String(path.dropFirst(projectPath.count + 1))
        }
        return path
    }
    
    /// Get file name from path
    var fileName: String {
        guard let path = filePath else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    
    /// Get directory name from path
    var directoryName: String {
        guard let path = filePath else { return "" }
        return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }
}

// MARK: - UserPreferences Extensions

extension UserPreferences {
    /// Get recent projects as URLs
    var recentProjectURLs: [URL] {
        return (recentProjects ?? []).compactMap { URL(fileURLWithPath: $0) }
    }
    
    /// Add project to recent list
    func addRecentProject(_ path: String) {
        var recent = recentProjects ?? []
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        
        if recent.count > maxRecentProjects {
            recent = Array(recent.prefix(Int(maxRecentProjects)))
        }
        
        recentProjects = recent
    }
    
    /// Remove project from recent list
    func removeRecentProject(_ path: String) {
        recentProjects?.removeAll { $0 == path }
    }
}

// MARK: - Supporting Types

struct ProjectStatistics {
    let totalKeys: Int
    let totalTranslations: Int
    let completedTranslations: Int
    let draftTranslations: Int
    let filesWithUsage: Int
    let completionPercentage: Double
}

struct TranslationValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    
    var hasIssues: Bool {
        return !errors.isEmpty || !warnings.isEmpty
    }
}

// MARK: - Fetch Request Extensions
//
//extension Project {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<Project> {
//        return NSFetchRequest<Project>(entityName: "Project")
//    }
//}
//
//extension I18nKey {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<I18nKey> {
//        return NSFetchRequest<I18nKey>(entityName: "I18nKey")
//    }
//}
//
//extension Translation {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<Translation> {
//        return NSFetchRequest<Translation>(entityName: "Translation")
//    }
//}
//
//extension FileUsage {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<FileUsage> {
//        return NSFetchRequest<FileUsage>(entityName: "FileUsage")
//    }
//}
//
//extension UserPreferences {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserPreferences> {
//        return NSFetchRequest<UserPreferences>(entityName: "UserPreferences")
//    }
//}
