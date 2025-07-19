//
//  RefactoringResultsView.swift
//  i18n editor
//
//  Created by PlusA on 19/07/2025.
//

import SwiftUI

/// Results view showing the outcome of refactoring operations
struct RefactoringResultsView: View {
    let result: SmartRefactoringResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Results summary header
                ResultsSummaryHeader(result: result)
                
                Divider()
                
                // Detailed results
                ScrollView {
                    VStack(spacing: 20) {
                        // Success section
                        if !result.appliedSuggestions.isEmpty {
                            SuccessSection(appliedSuggestions: result.appliedSuggestions)
                        }
                        
                        // Failed section
                        if !result.failedSuggestions.isEmpty {
                            FailedSection(failedSuggestions: result.failedSuggestions)
                        }
                        
                        // Modified files section
                        if !result.filesModified.isEmpty {
                            ModifiedFilesSection(files: result.filesModified)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Refactoring Results")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct ResultsSummaryHeader: View {
    let result: SmartRefactoringResult
    
    var isSuccess: Bool {
        result.failedSuggestions.isEmpty
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(isSuccess ? .green : .orange)
                    
                    Text("Refactoring Complete")
                        .font(.headline)
                }
                
                Text(summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Summary stats
            HStack(spacing: 16) {
                StatCard(
                    icon: "checkmark.circle",
                    value: "\(result.appliedSuggestions.count)",
                    label: "Applied",
                    color: .green
                )
                
                if !result.failedSuggestions.isEmpty {
                    StatCard(
                        icon: "xmark.circle",
                        value: "\(result.failedSuggestions.count)",
                        label: "Failed",
                        color: .red
                    )
                }
                
                StatCard(
                    icon: "doc.text",
                    value: "\(result.filesModified.count)",
                    label: "Files Modified",
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var summaryText: String {
        let total = result.appliedSuggestions.count + result.failedSuggestions.count
        if result.failedSuggestions.isEmpty {
            return "Successfully applied all \(total) refactoring suggestions"
        } else {
            return "Applied \(result.appliedSuggestions.count) of \(total) suggestions"
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

struct SuccessSection: View {
    let appliedSuggestions: [SmartRefactoringSuggestion]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                Text("Successfully Applied")
                    .font(.headline)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(appliedSuggestions) { suggestion in
                    AppliedSuggestionRow(suggestion: suggestion)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct FailedSection: View {
    let failedSuggestions: [SmartRefactoringSuggestion]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                
                Text("Failed to Apply")
                    .font(.headline)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(failedSuggestions) { suggestion in
                    FailedSuggestionRow(suggestion: suggestion)
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ModifiedFilesSection: View {
    let files: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Modified Files")
                    .font(.headline)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundColor(.blue)

                        Text(getRelativePath(file))
                            .font(.caption)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
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

struct AppliedSuggestionRow: View {
    let suggestion: SmartRefactoringSuggestion
    
    var body: some View {
        HStack {
            Text(suggestion.originalKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(suggestion.suggestedKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
                .fontWeight(.medium)
            
            Spacer()
            
            Text("\(suggestion.affectedFileCount) files")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct FailedSuggestionRow: View {
    let suggestion: SmartRefactoringSuggestion
    
    var body: some View {
        HStack {
            Text(suggestion.originalKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(suggestion.suggestedKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.red)
                .fontWeight(.medium)
            
            Spacer()
            
            Text("Failed")
                .font(.caption2)
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

struct RefactoringResultsView_Previews: PreviewProvider {
    static var previews: some View {
        let result = SmartRefactoringResult(
            appliedSuggestions: [
                SmartRefactoringSuggestion(
                    originalKey: "welcome",
                    suggestedKey: "home.welcome",
                    namespace: "home",
                    affectedFiles: ["/project/src/routes/+page.svelte"],
                    confidence: 0.9,
                    reason: "Used in home route"
                )
            ],
            failedSuggestions: [
                SmartRefactoringSuggestion(
                    originalKey: "error",
                    suggestedKey: "common.error",
                    namespace: "common",
                    affectedFiles: ["/project/src/lib/error.svelte"],
                    confidence: 0.7,
                    reason: "Permission denied"
                )
            ],
            filesModified: ["/project/src/routes/+page.svelte"],
            keysUpdated: 1
        )
        
        return RefactoringResultsView(result: result)
    }
}
