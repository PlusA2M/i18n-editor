//
//  RouteBasedRefactoring.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import SwiftUI

/// Intelligent key refactoring system based on SvelteKit route structure
class RouteBasedRefactoring: ObservableObject {
    @Published var isAnalyzing = false
    @Published var refactoringSuggestions: [RefactoringSuggestion] = []
    @Published var pendingRefactorings: [PendingRefactoring] = []
    
    private let dataManager = DataManager.shared
    private let fileSystemManager = FileSystemManager()
    
    // MARK: - Analysis and Suggestion Generation
    
    /// Analyze project structure and generate refactoring suggestions
    func analyzeProjectForRefactoring(_ project: Project) async -> [RefactoringSuggestion] {
        await MainActor.run {
            isAnalyzing = true
        }
        
        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }
        
        guard let projectPath = project.path else { return [] }
        
        // Scan project structure
        let routeStructure = await analyzeRouteStructure(projectPath: projectPath)
        let i18nKeys = dataManager.getI18nKeys(for: project)
        
        var suggestions: [RefactoringSuggestion] = []
        
        // Analyze each key for refactoring opportunities
        for key in i18nKeys {
            let keySuggestions = await analyzeKeyForRefactoring(key, routeStructure: routeStructure)
            suggestions.append(contentsOf: keySuggestions)
        }
        
        // Group and prioritize suggestions
        suggestions = prioritizeSuggestions(suggestions)
        
        await MainActor.run {
            refactoringSuggestions = suggestions
        }
        
        return suggestions
    }
    
    /// Analyze SvelteKit route structure
    private func analyzeRouteStructure(projectPath: String) async -> RouteStructure {
        let srcPath = URL(fileURLWithPath: projectPath).appendingPathComponent("src")
        let routesPath = srcPath.appendingPathComponent("routes")
        
        guard FileManager.default.fileExists(atPath: routesPath.path) else {
            return RouteStructure(routes: [], components: [])
        }
        
        var routes: [RouteInfo] = []
        var components: [ComponentInfo] = []
        
        // Scan routes directory
        do {
            let routeFiles = try fileSystemManager.getAllFiles(in: routesPath, withExtension: "svelte")
            
            for fileURL in routeFiles {
                let relativePath = String(fileURL.path.dropFirst(routesPath.path.count + 1))
                
                if let routeInfo = parseRouteFile(relativePath, fullPath: fileURL.path) {
                    routes.append(routeInfo)
                }
            }
            
            // Scan components directory
            let componentsPath = srcPath.appendingPathComponent("lib").appendingPathComponent("components")
            if FileManager.default.fileExists(atPath: componentsPath.path) {
                let componentFiles = try fileSystemManager.getAllFiles(in: componentsPath, withExtension: "svelte")
                
                for fileURL in componentFiles {
                    let relativePath = String(fileURL.path.dropFirst(componentsPath.path.count + 1))
                    
                    if let componentInfo = parseComponentFile(relativePath, fullPath: fileURL.path) {
                        components.append(componentInfo)
                    }
                }
            }
            
        } catch {
            print("Error analyzing route structure: \(error)")
        }
        
        return RouteStructure(routes: routes, components: components)
    }
    
    /// Parse route file to extract route information
    private func parseRouteFile(_ relativePath: String, fullPath: String) -> RouteInfo? {
        let pathComponents = relativePath.components(separatedBy: "/")
        
        // Remove file extension
        let cleanComponents = pathComponents.map { component in
            component.replacingOccurrences(of: "+page.svelte", with: "")
                .replacingOccurrences(of: "+layout.svelte", with: "")
                .replacingOccurrences(of: ".svelte", with: "")
        }.filter { !$0.isEmpty }
        
        let routePath = cleanComponents.joined(separator: "/")
        let routeName = cleanComponents.isEmpty ? "home" : cleanComponents.last ?? ""
        
        // Determine route type
        let routeType: RouteType
        if relativePath.contains("+layout.svelte") {
            routeType = .layout
        } else if relativePath.contains("+page.svelte") {
            routeType = .page
        } else {
            routeType = .component
        }
        
        return RouteInfo(
            name: routeName,
            path: routePath,
            fullPath: routePath,
            filePath: fullPath,
            type: routeType,
            depth: cleanComponents.count
        )
    }
    
    /// Parse component file to extract component information
    private func parseComponentFile(_ relativePath: String, fullPath: String) -> ComponentInfo? {
        let fileName = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
        
        return ComponentInfo(
            name: fileName,
            filePath: fullPath,
            category: determineComponentCategory(fileName)
        )
    }
    
    /// Determine component category based on naming patterns
    private func determineComponentCategory(_ fileName: String) -> ComponentCategory {
        let lowercaseName = fileName.lowercased()
        
        if lowercaseName.contains("button") || lowercaseName.contains("btn") {
            return .button
        } else if lowercaseName.contains("form") || lowercaseName.contains("input") {
            return .form
        } else if lowercaseName.contains("modal") || lowercaseName.contains("dialog") {
            return .modal
        } else if lowercaseName.contains("nav") || lowercaseName.contains("menu") {
            return .navigation
        } else if lowercaseName.contains("card") || lowercaseName.contains("item") {
            return .display
        } else {
            return .other
        }
    }
    
    /// Analyze individual key for refactoring opportunities
    private func analyzeKeyForRefactoring(_ key: I18nKey, routeStructure: RouteStructure) async -> [RefactoringSuggestion] {
        var suggestions: [RefactoringSuggestion] = []
        
        guard let keyName = key.key else { return suggestions }
        
        // Analyze usage patterns
        let usages = key.activeFileUsages
        let usagesByRoute = groupUsagesByRoute(usages, routeStructure: routeStructure)
        
        // Suggest route-based organization
        if let routeSuggestion = suggestRouteBasedOrganization(key: key, usagesByRoute: usagesByRoute) {
            suggestions.append(routeSuggestion)
        }
        
        // Suggest component-based organization
        if let componentSuggestion = suggestComponentBasedOrganization(key: key, usages: usages, routeStructure: routeStructure) {
            suggestions.append(componentSuggestion)
        }
        
        // Suggest namespace consolidation
        if let namespaceSuggestion = suggestNamespaceConsolidation(key: key, routeStructure: routeStructure) {
            suggestions.append(namespaceSuggestion)
        }
        
        return suggestions
    }
    
    /// Group key usages by route
    private func groupUsagesByRoute(_ usages: [FileUsage], routeStructure: RouteStructure) -> [String: [FileUsage]] {
        var usagesByRoute: [String: [FileUsage]] = [:]
        
        for usage in usages {
            guard let filePath = usage.filePath else { continue }
            
            // Find matching route
            let matchingRoute = routeStructure.routes.first { route in
                filePath.contains(route.path) || filePath.contains(route.name)
            }
            
            let routeKey = matchingRoute?.fullPath ?? "unknown"
            
            if usagesByRoute[routeKey] == nil {
                usagesByRoute[routeKey] = []
            }
            usagesByRoute[routeKey]?.append(usage)
        }
        
        return usagesByRoute
    }
    
    /// Suggest route-based key organization
    private func suggestRouteBasedOrganization(key: I18nKey, usagesByRoute: [String: [FileUsage]]) -> RefactoringSuggestion? {
        guard let keyName = key.key else { return nil }
        
        // Find the route with the most usages
        let sortedRoutes = usagesByRoute.sorted { $0.value.count > $1.value.count }
        
        guard let primaryRoute = sortedRoutes.first,
              primaryRoute.value.count >= 2, // At least 2 usages in the route
              primaryRoute.value.count > usagesByRoute.values.reduce(0, { $0 + $1.count }) / 2 else { // More than half of total usages
            return nil
        }
        
        let routePath = primaryRoute.key
        let suggestedKey = "\(routePath).\(keyName)"
        
        // Don't suggest if already follows this pattern
        if keyName.hasPrefix("\(routePath).") {
            return nil
        }
        
        return RefactoringSuggestion(
            id: UUID(),
            originalKey: keyName,
            suggestedKey: suggestedKey,
            type: .routeBased,
            reason: "Key is primarily used in '\(routePath)' route (\(primaryRoute.value.count) usages)",
            confidence: calculateConfidence(primaryUsages: primaryRoute.value.count, totalUsages: key.activeFileUsages.count),
            affectedFiles: primaryRoute.value.compactMap { $0.filePath },
            estimatedImpact: .medium,
            autoApplicable: true
        )
    }
    
    /// Suggest component-based key organization
    private func suggestComponentBasedOrganization(key: I18nKey, usages: [FileUsage], routeStructure: RouteStructure) -> RefactoringSuggestion? {
        guard let keyName = key.key else { return nil }
        
        // Find component usages
        let componentUsages = usages.filter { usage in
            guard let filePath = usage.filePath else { return false }
            return routeStructure.components.contains { component in
                filePath.contains(component.name)
            }
        }
        
        guard componentUsages.count >= 2 else { return nil }
        
        // Find the most used component
        let componentUsagesByName = Dictionary(grouping: componentUsages) { usage in
            routeStructure.components.first { component in
                usage.filePath?.contains(component.name) == true
            }?.name ?? "unknown"
        }
        
        guard let primaryComponent = componentUsagesByName.max(by: { $0.value.count < $1.value.count }) else {
            return nil
        }
        
        let suggestedKey = "components.\(primaryComponent.key).\(keyName)"
        
        // Don't suggest if already follows this pattern
        if keyName.hasPrefix("components.\(primaryComponent.key).") {
            return nil
        }
        
        return RefactoringSuggestion(
            id: UUID(),
            originalKey: keyName,
            suggestedKey: suggestedKey,
            type: .componentBased,
            reason: "Key is primarily used in '\(primaryComponent.key)' component (\(primaryComponent.value.count) usages)",
            confidence: calculateConfidence(primaryUsages: primaryComponent.value.count, totalUsages: usages.count),
            affectedFiles: primaryComponent.value.compactMap { $0.filePath },
            estimatedImpact: .low,
            autoApplicable: true
        )
    }
    
    /// Suggest namespace consolidation
    private func suggestNamespaceConsolidation(key: I18nKey, routeStructure: RouteStructure) -> RefactoringSuggestion? {
        guard let keyName = key.key else { return nil }
        
        // Check if key has inconsistent namespace
        let components = keyName.components(separatedBy: ".")
        
        if components.count > 3 { // Very nested key
            let suggestedKey = components.prefix(2).joined(separator: ".") + "." + components.last!
            
            return RefactoringSuggestion(
                id: UUID(),
                originalKey: keyName,
                suggestedKey: suggestedKey,
                type: .namespaceConsolidation,
                reason: "Key has excessive nesting (\(components.count) levels)",
                confidence: 0.6,
                affectedFiles: key.activeFileUsages.compactMap { $0.filePath },
                estimatedImpact: .low,
                autoApplicable: false
            )
        }
        
        return nil
    }
    
    /// Calculate confidence score for refactoring suggestion
    private func calculateConfidence(primaryUsages: Int, totalUsages: Int) -> Double {
        guard totalUsages > 0 else { return 0.0 }
        
        let ratio = Double(primaryUsages) / Double(totalUsages)
        
        if ratio >= 0.8 {
            return 0.9
        } else if ratio >= 0.6 {
            return 0.7
        } else if ratio >= 0.4 {
            return 0.5
        } else {
            return 0.3
        }
    }
    
    /// Prioritize suggestions based on impact and confidence
    private func prioritizeSuggestions(_ suggestions: [RefactoringSuggestion]) -> [RefactoringSuggestion] {
        return suggestions.sorted { suggestion1, suggestion2 in
            // First by confidence
            if suggestion1.confidence != suggestion2.confidence {
                return suggestion1.confidence > suggestion2.confidence
            }
            
            // Then by impact
            let impact1 = suggestion1.estimatedImpact.rawValue
            let impact2 = suggestion2.estimatedImpact.rawValue
            
            if impact1 != impact2 {
                return impact1 > impact2
            }
            
            // Finally by number of affected files
            return suggestion1.affectedFiles.count > suggestion2.affectedFiles.count
        }
    }
    
    // MARK: - Refactoring Execution
    
    /// Apply refactoring suggestion
    func applyRefactoring(_ suggestion: RefactoringSuggestion, project: Project) async -> RefactoringResult {
        let pendingRefactoring = PendingRefactoring(
            suggestion: suggestion,
            status: .inProgress,
            startedAt: Date()
        )
        
        await MainActor.run {
            pendingRefactorings.append(pendingRefactoring)
        }
        
        do {
            // Update key in database
            if let key = dataManager.getI18nKey(key: suggestion.originalKey, project: project) {
                key.key = suggestion.suggestedKey
                
                // Update all translations
                for translation in key.allTranslations {
                    // Translation objects remain the same, just the key reference changes
                }
                
                try dataManager.viewContext.save()
            }
            
            // Update usage in files (if auto-applicable)
            if suggestion.autoApplicable {
                let updateResult = await updateKeyUsageInFiles(suggestion)
                
                if !updateResult.success {
                    throw RefactoringError.fileUpdateFailed(updateResult.errors)
                }
            }
            
            await MainActor.run {
                if let index = pendingRefactorings.firstIndex(where: { $0.id == pendingRefactoring.id }) {
                    pendingRefactorings[index].status = .completed
                    pendingRefactorings[index].completedAt = Date()
                }
            }
            
            return RefactoringResult(
                success: true,
                originalKey: suggestion.originalKey,
                newKey: suggestion.suggestedKey,
                filesUpdated: suggestion.affectedFiles.count,
                errors: []
            )
            
        } catch {
            await MainActor.run {
                if let index = pendingRefactorings.firstIndex(where: { $0.id == pendingRefactoring.id }) {
                    pendingRefactorings[index].status = .failed
                    pendingRefactorings[index].error = error.localizedDescription
                }
            }
            
            return RefactoringResult(
                success: false,
                originalKey: suggestion.originalKey,
                newKey: suggestion.suggestedKey,
                filesUpdated: 0,
                errors: [error.localizedDescription]
            )
        }
    }
    
    /// Update key usage in source files
    private func updateKeyUsageInFiles(_ suggestion: RefactoringSuggestion) async -> FileUpdateResult {
        var updatedFiles: [String] = []
        var errors: [String] = []
        
        for filePath in suggestion.affectedFiles {
            do {
                let content = try String(contentsOf: URL(fileURLWithPath: filePath))
                
                // Replace key usage patterns
                let updatedContent = content.replacingOccurrences(
                    of: "m.\(suggestion.originalKey)",
                    with: "m.\(suggestion.suggestedKey)"
                )
                
                // Write back to file
                try updatedContent.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
                updatedFiles.append(filePath)
                
            } catch {
                errors.append("Failed to update \(filePath): \(error.localizedDescription)")
            }
        }
        
        return FileUpdateResult(
            success: errors.isEmpty,
            updatedFiles: updatedFiles,
            errors: errors
        )
    }
    
    /// Batch apply multiple refactoring suggestions
    func batchApplyRefactorings(_ suggestions: [RefactoringSuggestion], project: Project) async -> [RefactoringResult] {
        var results: [RefactoringResult] = []
        
        for suggestion in suggestions {
            let result = await applyRefactoring(suggestion, project: project)
            results.append(result)
            
            // Small delay between refactorings to avoid overwhelming the system
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        return results
    }
}

// MARK: - Supporting Types

struct RouteStructure {
    let routes: [RouteInfo]
    let components: [ComponentInfo]
}

struct RouteInfo {
    let name: String
    let path: String
    let fullPath: String
    let filePath: String
    let type: RouteType
    let depth: Int
}

struct ComponentInfo {
    let name: String
    let filePath: String
    let category: ComponentCategory
}

enum RouteType {
    case page
    case layout
    case component
}

enum ComponentCategory {
    case button
    case form
    case modal
    case navigation
    case display
    case other
}

struct RefactoringSuggestion: Identifiable {
    let id: UUID
    let originalKey: String
    let suggestedKey: String
    let type: RefactoringType
    let reason: String
    let confidence: Double
    let affectedFiles: [String]
    let estimatedImpact: RefactoringImpact
    let autoApplicable: Bool
}

enum RefactoringType {
    case routeBased
    case componentBased
    case namespaceConsolidation
    case duplicationRemoval
}

enum RefactoringImpact: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

struct PendingRefactoring: Identifiable {
    let id = UUID()
    let suggestion: RefactoringSuggestion
    var status: RefactoringStatus
    let startedAt: Date
    var completedAt: Date?
    var error: String?
}

enum RefactoringStatus {
    case pending
    case inProgress
    case completed
    case failed
}

struct RefactoringResult {
    let success: Bool
    let originalKey: String
    let newKey: String
    let filesUpdated: Int
    let errors: [String]
}

struct FileUpdateResult {
    let success: Bool
    let updatedFiles: [String]
    let errors: [String]
}

enum RefactoringError: Error {
    case fileUpdateFailed([String])
    case keyNotFound(String)
    case invalidSuggestion(String)
}

// MARK: - Refactoring UI Components

struct RefactoringSuggestionsView: View {
    let project: Project
    @StateObject private var refactoringSystem = RouteBasedRefactoring()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSuggestions: Set<UUID> = []
    @State private var showingBatchConfirmation = false
    @State private var isApplyingRefactorings = false

    var body: some View {
        NavigationView {
            VStack {
                // Header with statistics
                if !refactoringSystem.refactoringSuggestions.isEmpty {
                    RefactoringSummaryView(suggestions: refactoringSystem.refactoringSuggestions)
                        .padding()
                }

                // Suggestions list
                if refactoringSystem.isAnalyzing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)

                        Text("Analyzing project structure...")
                            .font(.headline)

                        Text("This may take a moment for large projects")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if refactoringSystem.refactoringSuggestions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.green)

                        Text("No Refactoring Suggestions")
                            .font(.headline)

                        Text("Your project structure looks well organized!")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(refactoringSystem.refactoringSuggestions) { suggestion in
                            RefactoringSuggestionRow(
                                suggestion: suggestion,
                                isSelected: selectedSuggestions.contains(suggestion.id)
                            ) {
                                toggleSelection(suggestion.id)
                            } onApply: {
                                applySingleRefactoring(suggestion)
                            }
                        }
                    }
                }

                // Pending refactorings
                if !refactoringSystem.pendingRefactorings.isEmpty {
                    PendingRefactoringsView(pendingRefactorings: refactoringSystem.pendingRefactorings)
                }
            }
            .navigationTitle("Refactoring Suggestions")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Refresh") {
                        Task {
                            await refactoringSystem.analyzeProjectForRefactoring(project)
                        }
                    }
                    .disabled(refactoringSystem.isAnalyzing)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    if !selectedSuggestions.isEmpty {
                        Button("Apply Selected") {
                            showingBatchConfirmation = true
                        }
                        .disabled(isApplyingRefactorings)
                    }

                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            Task {
                await refactoringSystem.analyzeProjectForRefactoring(project)
            }
        }
        .alert("Apply Refactorings", isPresented: $showingBatchConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Apply \(selectedSuggestions.count) Changes") {
                applySelectedRefactorings()
            }
        } message: {
            Text("Are you sure you want to apply \(selectedSuggestions.count) refactoring suggestions? This will modify your source files.")
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedSuggestions.contains(id) {
            selectedSuggestions.remove(id)
        } else {
            selectedSuggestions.insert(id)
        }
    }

    private func applySingleRefactoring(_ suggestion: RefactoringSuggestion) {
        Task {
            await refactoringSystem.applyRefactoring(suggestion, project: project)
        }
    }

    private func applySelectedRefactorings() {
        let suggestions = refactoringSystem.refactoringSuggestions.filter {
            selectedSuggestions.contains($0.id)
        }

        isApplyingRefactorings = true

        Task {
            await refactoringSystem.batchApplyRefactorings(suggestions, project: project)

            await MainActor.run {
                isApplyingRefactorings = false
                selectedSuggestions.removeAll()
            }
        }
    }
}

struct RefactoringSummaryView: View {
    let suggestions: [RefactoringSuggestion]

    var body: some View {
        HStack(spacing: 20) {
            SummaryItem(
                title: "Total Suggestions",
                value: "\(suggestions.count)",
                color: .blue
            )

            SummaryItem(
                title: "High Confidence",
                value: "\(suggestions.filter { $0.confidence >= 0.8 }.count)",
                color: .green
            )

            SummaryItem(
                title: "Auto-Applicable",
                value: "\(suggestions.filter { $0.autoApplicable }.count)",
                color: .orange
            )

            SummaryItem(
                title: "High Impact",
                value: "\(suggestions.filter { $0.estimatedImpact == .high }.count)",
                color: .red
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SummaryItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct RefactoringSuggestionRow: View {
    let suggestion: RefactoringSuggestion
    let isSelected: Bool
    let onToggle: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack {
            // Selection checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text(suggestion.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(suggestion.type.color.opacity(0.2))
                        .foregroundColor(suggestion.type.color)
                        .cornerRadius(4)

                    Spacer()

                    ConfidenceIndicator(confidence: suggestion.confidence)
                    ImpactIndicator(impact: suggestion.estimatedImpact)

                    if suggestion.autoApplicable {
                        Text("Auto")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                    }
                }

                // Key change
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("From:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(suggestion.originalKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)
                    }

                    HStack {
                        Text("To:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(suggestion.suggestedKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }

                // Reason
                Text(suggestion.reason)
                    .font(.body)
                    .foregroundColor(.primary)

                // Affected files
                Text("\(suggestion.affectedFiles.count) file(s) affected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Apply button
            Button("Apply") {
                onApply()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }
}

struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 2) {
            Text("Confidence:")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("\(Int(confidence * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(confidenceColor)
        }
    }

    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
}

struct ImpactIndicator: View {
    let impact: RefactoringImpact

    var body: some View {
        Text(impact.displayName)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(impact.color.opacity(0.2))
            .foregroundColor(impact.color)
            .cornerRadius(3)
    }
}

struct PendingRefactoringsView: View {
    let pendingRefactorings: [PendingRefactoring]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pending Refactorings")
                .font(.headline)

            ForEach(pendingRefactorings) { pending in
                HStack {
                    statusIcon(for: pending.status)

                    Text(pending.suggestion.originalKey)
                        .font(.system(.caption, design: .monospaced))

                    Text("→")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(pending.suggestion.suggestedKey)
                        .font(.system(.caption, design:.monospaced))

                    Spacer()

                    Text(pending.status.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func statusIcon(for status: RefactoringStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.orange)
            case .inProgress:
                ProgressView()
                    .scaleEffect(0.8)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.caption)
    }
}

// MARK: - Extensions

extension RefactoringType {
    var displayName: String {
        switch self {
        case .routeBased: return "Route-based"
        case .componentBased: return "Component-based"
        case .namespaceConsolidation: return "Namespace"
        case .duplicationRemoval: return "Deduplication"
        }
    }

    var color: Color {
        switch self {
        case .routeBased: return .blue
        case .componentBased: return .green
        case .namespaceConsolidation: return .orange
        case .duplicationRemoval: return .purple
        }
    }
}

extension RefactoringStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}
