//
//  RefactoringSuggestionsView.swift
//  i18n editor
//
//  Created by PlusA on 19/07/2025.
//

import SwiftUI

/// View for displaying and managing smart refactoring suggestions
struct SmartRefactoringSuggestionsView: View {
    let suggestions: [SmartRefactoringSuggestion]
    @Binding var selectedSuggestions: Set<SmartRefactoringSuggestion>
    let onPreview: () -> Void
    let onApply: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with summary
            SuggestionsHeader(
                totalSuggestions: suggestions.count,
                selectedCount: selectedSuggestions.count,
                onPreview: onPreview,
                onApply: onApply
            )
            
            Divider()
            
            // Suggestions list
            if suggestions.isEmpty {
                EmptySuggestionsView()
            } else {
                SuggestionsList(
                    suggestions: suggestions,
                    selectedSuggestions: $selectedSuggestions
                )
            }
        }
    }
}

struct SuggestionsHeader: View {
    let totalSuggestions: Int
    let selectedCount: Int
    let onPreview: () -> Void
    let onApply: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Refactoring Suggestions")
                    .font(.headline)
                
                Text("\(totalSuggestions) suggestions found, \(selectedCount) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Preview") {
                    onPreview()
                }
                .disabled(selectedCount == 0)
                .buttonStyle(.bordered)
                
                Button("Apply Selected") {
                    onApply()
                }
                .disabled(selectedCount == 0)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct EmptySuggestionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("No Refactoring Suggestions")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your project structure is already well-organized!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct SuggestionsList: View {
    let suggestions: [SmartRefactoringSuggestion]
    @Binding var selectedSuggestions: Set<SmartRefactoringSuggestion>

    var groupedSuggestions: [(String, [SmartRefactoringSuggestion])] {
        let grouped = Dictionary(grouping: suggestions) { $0.namespace }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedSuggestions, id: \.0) { namespace, namespaceSuggestions in
                    NamespaceSection(
                        namespace: namespace,
                        suggestions: namespaceSuggestions,
                        selectedSuggestions: $selectedSuggestions
                    )
                }
            }
        }
    }
}

struct NamespaceSection: View {
    let namespace: String
    let suggestions: [SmartRefactoringSuggestion]
    @Binding var selectedSuggestions: Set<SmartRefactoringSuggestion>
    @State private var isExpanded = true
    
    var allSelected: Bool {
        suggestions.allSatisfy { selectedSuggestions.contains($0) }
    }
    
    var someSelected: Bool {
        suggestions.contains { selectedSuggestions.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Namespace header
            HStack {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(namespace)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("(\(suggestions.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selectedSuggestions.subtract(suggestions)
                    } else {
                        selectedSuggestions.formUnion(suggestions)
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Suggestions in this namespace
            if isExpanded {
                ForEach(suggestions) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        isSelected: selectedSuggestions.contains(suggestion),
                        onToggle: { isSelected in
                            if isSelected {
                                selectedSuggestions.insert(suggestion)
                            } else {
                                selectedSuggestions.remove(suggestion)
                            }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    if suggestion != suggestions.last {
                        Divider()
                            .padding(.leading)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

struct SuggestionRow: View {
    let suggestion: SmartRefactoringSuggestion
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: { onToggle(!isSelected) }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Key transformation
                HStack {
                    Text(suggestion.originalKey)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(suggestion.suggestedKey)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }
                
                // Reason and confidence
                HStack {
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    ConfidenceBadge(confidence: suggestion.confidence)
                }
                
                // Affected files preview
                if !suggestion.affectedFiles.isEmpty {
                    AffectedFilesPreview(files: suggestion.affectedFiles)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: Double
    
    var color: Color {
        switch confidence {
        case 0.8...:
            return .green
        case 0.6..<0.8:
            return .orange
        default:
            return .red
        }
    }
    
    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct AffectedFilesPreview: View {
    let files: [String]

    var displayFiles: [String] {
        Array(files.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(displayFiles.enumerated()), id: \.offset) { index, file in
                Text(getRelativeProjectPath(file))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if files.count > 3 {
                Text("+ \(files.count - 3) more files")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.leading, 8)
    }

    private func getRelativeProjectPath(_ fullPath: String) -> String {
        // Try to find common project root indicators
        let projectIndicators = ["src/", "package.json", "svelte.config", "vite.config"]

        for indicator in projectIndicators {
            if let range = fullPath.range(of: indicator) {
                // If we find src/, include it in the path
                if indicator == "src/" {
                    return String(fullPath[range.lowerBound...])
                } else {
                    // For other indicators, find the directory containing them
                    let pathBeforeIndicator = String(fullPath[..<range.lowerBound])
                    if let lastSlash = pathBeforeIndicator.lastIndex(of: "/") {
                        let projectRoot = String(fullPath[fullPath.index(after: lastSlash)...])
                        return projectRoot
                    }
                }
            }
        }

        // Fallback: try to find a reasonable relative path
        let components = fullPath.components(separatedBy: "/")
        if let srcIndex = components.firstIndex(of: "src") {
            return components[srcIndex...].joined(separator: "/")
        }

        // Last resort: just show the filename
        return URL(fileURLWithPath: fullPath).lastPathComponent
    }
}

// MARK: - Preview

struct SmartRefactoringSuggestionsView_Previews: PreviewProvider {
    static var previews: some View {
        let suggestions = [
            SmartRefactoringSuggestion(
                originalKey: "welcome",
                suggestedKey: "home.welcome",
                namespace: "home",
                affectedFiles: ["/src/routes/+page.svelte"],
                confidence: 0.9,
                reason: "Used in home route"
            ),
            SmartRefactoringSuggestion(
                originalKey: "title",
                suggestedKey: "articles.title",
                namespace: "articles",
                affectedFiles: ["/src/routes/articles/+page.svelte", "/src/routes/articles/[slug]/+page.svelte"],
                confidence: 0.8,
                reason: "Used in articles section"
            )
        ]
        
        return SmartRefactoringSuggestionsView(
            suggestions: suggestions,
            selectedSuggestions: .constant(Set(suggestions)),
            onPreview: {},
            onApply: {}
        )
        .frame(width: 800, height: 600)
    }
}
