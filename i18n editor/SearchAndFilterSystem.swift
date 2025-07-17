//
//  SearchAndFilterSystem.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import SwiftUI
import Combine

/// Comprehensive search and filtering system for i18n keys and translations
class SearchAndFilterSystem: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var searchFilters = SearchFilters()
    @Published var savedSearches: [SavedSearch] = []

    private var searchCancellable: AnyCancellable?
    private var project: Project?
    private let dataManager = DataManager.shared

    // MARK: - Search Configuration

    func configureSearch(for project: Project) {
        self.project = project
        loadSavedSearches()
        setupSearchDebouncing()
    }

    private func setupSearchDebouncing() {
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                self?.performSearch(searchText)
            }
    }

    // MARK: - Search Execution

    private func performSearch(_ query: String) {
        guard let project = project else { return }

        if query.isEmpty {
            searchResults = []
            return
        }

        isSearching = true

        Task {
            let results = await executeSearch(query: query, project: project)

            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    private func executeSearch(query: String, project: Project) async -> [SearchResult] {
        let i18nKeys = dataManager.getI18nKeys(for: project)
        var results: [SearchResult] = []

        // Search in keys
        for key in i18nKeys {
            let keyResults = searchInKey(key, query: query)
            results.append(contentsOf: keyResults)
        }

        // Apply filters
        results = applyFilters(results)

        // Sort results by relevance
        results = sortByRelevance(results, query: query)

        return results
    }

    private func searchInKey(_ key: I18nKey, query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let lowercaseQuery = query.lowercased()

        // Search in key name
        if let keyName = key.key, keyName.lowercased().contains(lowercaseQuery) {
            let relevance = calculateRelevance(text: keyName, query: query)
            results.append(SearchResult(
                type: .key,
                key: key,
                matchedText: keyName,
                context: "Key name",
                relevance: relevance,
                locale: nil
            ))
        }

        // Search in namespace
        if let namespace = key.namespace, namespace.lowercased().contains(lowercaseQuery) {
            let relevance = calculateRelevance(text: namespace, query: query)
            results.append(SearchResult(
                type: .namespace,
                key: key,
                matchedText: namespace,
                context: "Namespace",
                relevance: relevance,
                locale: nil
            ))
        }

        // Search in translations
        for translation in key.allTranslations {
            if let value = translation.effectiveValue, value.lowercased().contains(lowercaseQuery) {
                let relevance = calculateRelevance(text: value, query: query)
                results.append(SearchResult(
                    type: .translation,
                    key: key,
                    matchedText: value,
                    context: "Translation value",
                    relevance: relevance,
                    locale: translation.locale
                ))
            }
        }

        // Search in file paths
        for usage in key.activeFileUsages {
            if let filePath = usage.filePath, filePath.lowercased().contains(lowercaseQuery) {
                let relevance = calculateRelevance(text: filePath, query: query)
                results.append(SearchResult(
                    type: .filePath,
                    key: key,
                    matchedText: filePath,
                    context: "File path",
                    relevance: relevance,
                    locale: nil
                ))
            }
        }

        return results
    }

    private func calculateRelevance(text: String, query: String) -> Double {
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()

        // Exact match gets highest score
        if lowercaseText == lowercaseQuery {
            return 1.0
        }

        // Starts with query gets high score
        if lowercaseText.hasPrefix(lowercaseQuery) {
            return 0.8
        }

        // Contains query as whole word gets medium score
        if lowercaseText.contains(" \(lowercaseQuery) ") ||
           lowercaseText.contains(".\(lowercaseQuery).") ||
           lowercaseText.contains("_\(lowercaseQuery)_") {
            return 0.6
        }

        // Contains query gets lower score
        if lowercaseText.contains(lowercaseQuery) {
            return 0.4
        }

        return 0.0
    }

    private func applyFilters(_ results: [SearchResult]) -> [SearchResult] {
        var filteredResults = results

        // Filter by type
        if !searchFilters.includeKeys && !searchFilters.includeTranslations &&
           !searchFilters.includeFilePaths && !searchFilters.includeNamespaces {
            // If no specific types selected, include all
        } else {
            filteredResults = filteredResults.filter { result in
                switch result.type {
                case .key:
                    return searchFilters.includeKeys
                case .translation:
                    return searchFilters.includeTranslations
                case .filePath:
                    return searchFilters.includeFilePaths
                case .namespace:
                    return searchFilters.includeNamespaces
                }
            }
        }

        // Filter by locale
        if !searchFilters.selectedLocales.isEmpty {
            filteredResults = filteredResults.filter { result in
                guard let locale = result.locale else { return true } // Include non-locale results
                return searchFilters.selectedLocales.contains(locale)
            }
        }

        // Filter by usage status
        switch searchFilters.usageFilter {
        case .all:
            break
        case .used:
            filteredResults = filteredResults.filter { $0.key.isUsedInFiles }
        case .unused:
            filteredResults = filteredResults.filter { !$0.key.isUsedInFiles }
        }

        // Filter by completion status
        switch searchFilters.completionFilter {
        case .all:
            break
        case .complete:
            filteredResults = filteredResults.filter { $0.key.completionPercentage >= 1.0 }
        case .incomplete:
            filteredResults = filteredResults.filter { $0.key.completionPercentage < 1.0 }
        case .missing:
            filteredResults = filteredResults.filter { $0.key.hasMissingTranslations }
        }

        return filteredResults
    }

    private func sortByRelevance(_ results: [SearchResult], query: String) -> [SearchResult] {
        return results.sorted { result1, result2 in
            // First sort by relevance
            if result1.relevance != result2.relevance {
                return result1.relevance > result2.relevance
            }

            // Then by type priority
            let typePriority: [SearchResultType: Int] = [
                .key: 4,
                .namespace: 3,
                .translation: 2,
                .filePath: 1
            ]

            let priority1 = typePriority[result1.type] ?? 0
            let priority2 = typePriority[result2.type] ?? 0

            if priority1 != priority2 {
                return priority1 > priority2
            }

            // Finally by alphabetical order
            return result1.matchedText < result2.matchedText
        }
    }

    // MARK: - Advanced Search Features

    func searchWithRegex(_ pattern: String) -> [SearchResult] {
        guard let project = project,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let i18nKeys = dataManager.getI18nKeys(for: project)
        var results: [SearchResult] = []

        for key in i18nKeys {
            // Search in key name
            if let keyName = key.key {
                let range = NSRange(location: 0, length: keyName.count)
                if regex.firstMatch(in: keyName, options: [], range: range) != nil {
                    results.append(SearchResult(
                        type: .key,
                        key: key,
                        matchedText: keyName,
                        context: "Regex match in key",
                        relevance: 0.8,
                        locale: nil
                    ))
                }
            }

            // Search in translations
            for translation in key.allTranslations {
                if let value = translation.effectiveValue {
                    let range = NSRange(location: 0, length: value.count)
                    if regex.firstMatch(in: value, options: [], range: range) != nil {
                        results.append(SearchResult(
                            type: .translation,
                            key: key,
                            matchedText: value,
                            context: "Regex match in translation",
                            relevance: 0.6,
                            locale: translation.locale
                        ))
                    }
                }
            }
        }

        return results
    }

    func searchByUsagePattern(_ pattern: UsagePattern) -> [SearchResult] {
        guard let project = project else { return [] }

        let i18nKeys = dataManager.getI18nKeys(for: project)
        var results: [SearchResult] = []

        for key in i18nKeys {
            var matches = false

            switch pattern {
            case .unusedKeys:
                matches = !key.isUsedInFiles
            case .overusedKeys(let threshold):
                matches = key.activeFileUsages.count > threshold
            case .keysInSpecificFiles(let filePattern):
                matches = key.activeFileUsages.contains { usage in
                    usage.filePath?.contains(filePattern) == true
                }
            case .recentlyModified(let days):
                let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))
                matches = (key.lastModified ?? Date.distantPast) > cutoffDate
            }

            if matches {
                results.append(SearchResult(
                    type: .key,
                    key: key,
                    matchedText: key.key ?? "",
                    context: "Usage pattern match",
                    relevance: 0.7,
                    locale: nil
                ))
            }
        }

        return results
    }

    // MARK: - Saved Searches

    func saveSearch(_ name: String) {
        let savedSearch = SavedSearch(
            name: name,
            query: searchText,
            filters: searchFilters,
            createdAt: Date()
        )

        savedSearches.append(savedSearch)
        saveSavedSearches()
    }

    func loadSavedSearch(_ savedSearch: SavedSearch) {
        searchText = savedSearch.query
        searchFilters = savedSearch.filters
    }

    func deleteSavedSearch(_ savedSearch: SavedSearch) {
        savedSearches.removeAll { $0.id == savedSearch.id }
        saveSavedSearches()
    }

    private func loadSavedSearches() {
        // Load from UserDefaults or Core Data
        // Simplified implementation
        savedSearches = []
    }

    private func saveSavedSearches() {
        // Save to UserDefaults or Core Data
        // Simplified implementation
    }

    // MARK: - Quick Filters

    func applyQuickFilter(_ filter: QuickFilter) {
        switch filter {
        case .missingTranslations:
            searchFilters.completionFilter = .missing
            searchText = ""
        case .unusedKeys:
            searchFilters.usageFilter = .unused
            searchText = ""
        case .recentlyModified:
            searchText = ""
            // Apply date filter
        case .draftChanges:
            searchText = ""
            // Filter for draft translations
        case .validationErrors:
            searchText = ""
            // Filter for validation errors
        }

        performSearch(searchText)
    }

    func clearAllFilters() {
        searchFilters = SearchFilters()
        searchText = ""
        searchResults = []
    }
}

// MARK: - Supporting Types

struct SearchResult: Identifiable {
    let id = UUID()
    let type: SearchResultType
    let key: I18nKey
    let matchedText: String
    let context: String
    let relevance: Double
    let locale: String?
}

enum SearchResultType {
    case key
    case translation
    case filePath
    case namespace
}

struct SearchFilters {
    var includeKeys = true
    var includeTranslations = true
    var includeFilePaths = true
    var includeNamespaces = true
    var selectedLocales: Set<String> = []
    var usageFilter: UsageFilter = .all
    var completionFilter: CompletionFilter = .all
    var caseSensitive = false
    var useRegex = false
}

enum UsageFilter {
    case all
    case used
    case unused
}

enum CompletionFilter {
    case all
    case complete
    case incomplete
    case missing
}

enum UsagePattern {
    case unusedKeys
    case overusedKeys(threshold: Int)
    case keysInSpecificFiles(pattern: String)
    case recentlyModified(days: Int)
}

enum QuickFilter {
    case missingTranslations
    case unusedKeys
    case recentlyModified
    case draftChanges
    case validationErrors
}

struct SavedSearch: Identifiable, Codable {
    let id = UUID()
    let name: String
    let query: String
    let filters: SearchFilters
    let createdAt: Date
}

// Make SearchFilters Codable
extension SearchFilters: Codable {
    enum CodingKeys: String, CodingKey {
        case includeKeys, includeTranslations, includeFilePaths, includeNamespaces
        case selectedLocales, usageFilter, completionFilter, caseSensitive, useRegex
    }
}

extension UsageFilter: Codable {}
extension CompletionFilter: Codable {}

// MARK: - Search UI Components

struct SearchAndFilterView: View {
    @StateObject private var searchSystem = SearchAndFilterSystem()
    let project: Project
    @Binding var selectedKeys: Set<String>

    @State private var showingAdvancedFilters = false
    @State private var showingSavedSearches = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBarView(searchSystem: searchSystem)

            // Quick filters
            QuickFiltersView(searchSystem: searchSystem, showingAdvancedFilters: $showingAdvancedFilters)

            // Advanced filters (collapsible)
            if showingAdvancedFilters {
                AdvancedFiltersView(searchSystem: searchSystem)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            // Search results
            SearchResultsView(
                searchSystem: searchSystem,
                selectedKeys: $selectedKeys
            )
        }
        .onAppear {
            searchSystem.configureSearch(for: project)
        }
    }
}

struct SearchBarView: View {
    @ObservedObject var searchSystem: SearchAndFilterSystem
    @State private var showingRegexHelp = false

    var body: some View {
        HStack {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            // Search field
            TextField("Search keys, translations, files...", text: $searchSystem.searchText)
                .textFieldStyle(.plain)

            // Loading indicator
            if searchSystem.isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            }

            // Clear button
            if !searchSystem.searchText.isEmpty {
                Button(action: { searchSystem.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Regex toggle
            Button(action: { searchSystem.searchFilters.useRegex.toggle() }) {
                Image(systemName: "textformat.alt")
                    .foregroundColor(searchSystem.searchFilters.useRegex ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help("Use regular expressions")
            .popover(isPresented: $showingRegexHelp) {
                RegexHelpView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct QuickFiltersView: View {
    @ObservedObject var searchSystem: SearchAndFilterSystem
    @Binding var showingAdvancedFilters: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                QuickFilterButton(title: "Missing", icon: "exclamationmark.triangle") {
                    searchSystem.applyQuickFilter(.missingTranslations)
                }

                QuickFilterButton(title: "Unused", icon: "link.slash") {
                    searchSystem.applyQuickFilter(.unusedKeys)
                }

                QuickFilterButton(title: "Recent", icon: "clock") {
                    searchSystem.applyQuickFilter(.recentlyModified)
                }

                QuickFilterButton(title: "Drafts", icon: "pencil.circle") {
                    searchSystem.applyQuickFilter(.draftChanges)
                }

                QuickFilterButton(title: "Errors", icon: "xmark.circle") {
                    searchSystem.applyQuickFilter(.validationErrors)
                }

                Divider()
                    .frame(height: 20)

                Button("Clear All") {
                    searchSystem.clearAllFilters()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Divider()
                    .frame(height: 20)

                Button(showingAdvancedFilters ? "Hide Filters" : "More Filters") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingAdvancedFilters.toggle()
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }
}

struct QuickFilterButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct AdvancedFiltersView: View {
    @ObservedObject var searchSystem: SearchAndFilterSystem

    var body: some View {
        VStack(spacing: 12) {
            // Filter types section
            VStack(alignment: .leading, spacing: 8) {
                Text("Search In:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack {
                    FilterToggle(title: "Keys", isOn: $searchSystem.searchFilters.includeKeys)
                    FilterToggle(title: "Translations", isOn: $searchSystem.searchFilters.includeTranslations)
                    FilterToggle(title: "File Paths", isOn: $searchSystem.searchFilters.includeFilePaths)
                    FilterToggle(title: "Namespaces", isOn: $searchSystem.searchFilters.includeNamespaces)
                }
            }

            // Usage filter section
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Picker("Usage Filter", selection: $searchSystem.searchFilters.usageFilter) {
                    Text("All").tag(UsageFilter.all)
                    Text("Used").tag(UsageFilter.used)
                    Text("Unused").tag(UsageFilter.unused)
                }
                .pickerStyle(.segmented)
            }

            // Completion filter section
            VStack(alignment: .leading, spacing: 8) {
                Text("Completion:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Picker("Completion Filter", selection: $searchSystem.searchFilters.completionFilter) {
                    Text("All").tag(CompletionFilter.all)
                    Text("Complete").tag(CompletionFilter.complete)
                    Text("Incomplete").tag(CompletionFilter.incomplete)
                    Text("Missing").tag(CompletionFilter.missing)
                }
                .pickerStyle(.segmented)
            }

            // Search options
            VStack(alignment: .leading, spacing: 8) {
                Text("Options:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack {
                    FilterToggle(title: "Case Sensitive", isOn: $searchSystem.searchFilters.caseSensitive)
                    FilterToggle(title: "Use Regex", isOn: $searchSystem.searchFilters.useRegex)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct FilterToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.square" : "square")
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isOn ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct SearchResultsView: View {
    @ObservedObject var searchSystem: SearchAndFilterSystem
    @Binding var selectedKeys: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Results header
            HStack {
                Text("\(searchSystem.searchResults.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !searchSystem.searchResults.isEmpty {
                    Button("Select All") {
                        for result in searchSystem.searchResults {
                            selectedKeys.insert(result.key.key ?? "")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Results list
            if searchSystem.searchResults.isEmpty && !searchSystem.searchText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundColor(.secondary)

                    Text("No results found")
                        .foregroundColor(.secondary)

                    Text("Try adjusting your search terms or filters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchSystem.searchResults) { result in
                            SearchResultRow(
                                result: result,
                                isSelected: selectedKeys.contains(result.key.key ?? "")
                            ) {
                                toggleSelection(result.key)
                            }

                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func toggleSelection(_ key: I18nKey) {
        let keyString = key.key ?? ""
        if selectedKeys.contains(keyString) {
            selectedKeys.remove(keyString)
        } else {
            selectedKeys.insert(keyString)
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            // Result type icon
            resultTypeIcon

            VStack(alignment: .leading, spacing: 2) {
                // Matched text with highlighting
                Text(result.matchedText)
                    .font(.body)
                    .lineLimit(2)

                // Context and key info
                HStack {
                    Text(result.context)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let locale = result.locale {
                        Text("• \(locale)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    Text(result.key.key ?? "")
                        .font(.system(.caption, design:.monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Relevance indicator
            Circle()
                .fill(relevanceColor)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var resultTypeIcon: some View {
        Group {
            switch result.type {
            case .key:
                Image(systemName: "key")
                    .foregroundColor(.blue)
            case .translation:
                Image(systemName: "textformat")
                    .foregroundColor(.green)
            case .filePath:
                Image(systemName: "doc")
                    .foregroundColor(.orange)
            case .namespace:
                Image(systemName: "folder")
                    .foregroundColor(.purple)
            }
        }
        .font(.caption)
    }

    private var relevanceColor: Color {
        if result.relevance >= 0.8 {
            return .green
        } else if result.relevance >= 0.6 {
            return .yellow
        } else {
            return .red
        }
    }
}

struct RegexHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Regular Expression Help")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Common patterns:")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                RegexHelpRow(pattern: "^hello", description: "Starts with 'hello'")
                RegexHelpRow(pattern: "world$", description: "Ends with 'world'")
                RegexHelpRow(pattern: ".*button.*", description: "Contains 'button'")
                RegexHelpRow(pattern: "[0-9]+", description: "Contains numbers")
                RegexHelpRow(pattern: "\\w+\\.\\w+", description: "Nested keys (word.word)")
            }
        }
        .padding()
        .frame(maxWidth: 300)
    }
}

struct RegexHelpRow: View {
    let pattern: String
    let description: String

    var body: some View {
        HStack {
            Text(pattern)
                .font(.system(.caption, design:.monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
