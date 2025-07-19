//
//  RefactoringPreviewView.swift
//  i18n editor
//
//  Created by PlusA on 19/07/2025.
//

import SwiftUI

/// Preview view for refactoring changes before applying them
struct RefactoringPreviewView: View {
    let suggestions: [SmartRefactoringSuggestion]
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Summary header
                PreviewSummaryHeader(suggestions: suggestions)
                
                Divider()
                
                // Changes preview
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            PreviewChangeRow(suggestion: suggestion)
                            
                            if suggestion != suggestions.last {
                                Divider()
                                    .padding(.leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Refactoring Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply Changes") {
                        onApply()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct PreviewSummaryHeader: View {
    let suggestions: [SmartRefactoringSuggestion]
    
    var totalFiles: Int {
        Set(suggestions.flatMap { $0.affectedFiles }).count
    }
    
    var namespaces: Set<String> {
        Set(suggestions.map { $0.namespace })
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview Changes")
                    .font(.headline)
                
                Text("\(suggestions.count) keys will be refactored across \(totalFiles) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Summary stats
            HStack(spacing: 16) {
                StatItem(
                    icon: "key",
                    value: "\(suggestions.count)",
                    label: "Keys"
                )
                
                StatItem(
                    icon: "folder",
                    value: "\(namespaces.count)",
                    label: "Namespaces"
                )
                
                StatItem(
                    icon: "doc.text",
                    value: "\(totalFiles)",
                    label: "Files"
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct PreviewChangeRow: View {
    let suggestion: SmartRefactoringSuggestion
    @State private var showingFiles = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Key transformation
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Before:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("m.\(suggestion.originalKey)()")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    
                    HStack {
                        Text("After:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("m[\"\(suggestion.suggestedKey)\"]()")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                ConfidenceBadge(confidence: suggestion.confidence)
            }
            
            // Namespace info
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text("Namespace: \(suggestion.namespace)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(showingFiles ? "Hide Files" : "Show Files (\(suggestion.affectedFileCount))") {
                    showingFiles.toggle()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // Affected files (expandable)
            if showingFiles {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(suggestion.affectedFiles.enumerated()), id: \.offset) { index, file in
                        HStack {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(getRelativePath(file))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .padding()
    }
    
    private func getRelativePath(_ fullPath: String) -> String {
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

struct RefactoringPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        let suggestions = [
            SmartRefactoringSuggestion(
                originalKey: "welcome",
                suggestedKey: "home.welcome",
                namespace: "home",
                affectedFiles: ["/project/src/routes/+page.svelte"],
                confidence: 0.9,
                reason: "Used in home route"
            ),
            SmartRefactoringSuggestion(
                originalKey: "title",
                suggestedKey: "articles.title",
                namespace: "articles",
                affectedFiles: [
                    "/project/src/routes/articles/+page.svelte",
                    "/project/src/routes/articles/[slug]/+page.svelte"
                ],
                confidence: 0.8,
                reason: "Used in articles section"
            )
        ]
        
        return RefactoringPreviewView(
            suggestions: suggestions,
            onApply: {}
        )
    }
}
