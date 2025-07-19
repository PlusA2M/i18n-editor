//
//  SmartRefactoringView.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI

/// Smart refactoring view for automatic key nesting based on SvelteKit route patterns
struct SmartRefactoringView: View {
    let project: Project
    @StateObject private var refactoringSystem = SmartRefactoringSystem()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSuggestions: Set<SmartRefactoringSuggestion> = []
    @State private var showingPreview = false
    @State private var showingResults = false
    @State private var refactoringResult: SmartRefactoringResult?
    @State private var hasAnalyzed = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with progress
                if refactoringSystem.isAnalyzing {
                    RefactoringProgressHeader(
                        progress: refactoringSystem.analysisProgress,
                        operation: refactoringSystem.currentOperation
                    )
                }

                // Main content
                if refactoringSystem.refactoringSuggestions.isEmpty && !refactoringSystem.isAnalyzing {
                    EmptyRefactoringState(
                        hasAnalyzed: hasAnalyzed,
                        onAnalyze: analyzeProject
                    )
                } else {
                    SmartRefactoringSuggestionsView(
                        suggestions: refactoringSystem.refactoringSuggestions,
                        selectedSuggestions: $selectedSuggestions,
                        onPreview: { showingPreview = true },
                        onApply: applySelectedSuggestions
                    )
                }
            }
            .navigationTitle("Smart Refactoring")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !refactoringSystem.refactoringSuggestions.isEmpty {
                        Button("Select All") {
                            selectedSuggestions = Set(refactoringSystem.refactoringSuggestions)
                        }
                        .disabled(refactoringSystem.isAnalyzing)

                        Button("Clear Selection") {
                            selectedSuggestions.removeAll()
                        }
                        .disabled(refactoringSystem.isAnalyzing || selectedSuggestions.isEmpty)
                    }

                    Button(hasAnalyzed && refactoringSystem.refactoringSuggestions.isEmpty ? "Re-analyze" : "Analyze") {
                        analyzeProject()
                    }
                    .disabled(refactoringSystem.isAnalyzing)
                    .buttonStyle(.borderedProminent)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .sheet(isPresented: $showingPreview) {
            RefactoringPreviewView(
                suggestions: Array(selectedSuggestions),
                onApply: applySelectedSuggestions
            )
        }
        .sheet(isPresented: $showingResults) {
            if let result = refactoringResult {
                RefactoringResultsView(result: result)
            }
        }
        .onAppear {
            if !hasAnalyzed {
                analyzeProject()
            }
        }
    }

    private func analyzeProject() {
        hasAnalyzed = true
        Task {
            await refactoringSystem.analyzeProject(project)
        }
    }

    private func applySelectedSuggestions() {
        guard !selectedSuggestions.isEmpty else { return }

        Task {
            let result = await refactoringSystem.applyRefactoring(Array(selectedSuggestions), project: project)

            await MainActor.run {
                refactoringResult = result
                showingResults = true
                showingPreview = false

                // Clear applied suggestions from selection
                selectedSuggestions = selectedSuggestions.subtracting(result.appliedSuggestions)

                // Remove applied suggestions from the list
                refactoringSystem.refactoringSuggestions.removeAll { suggestion in
                    result.appliedSuggestions.contains(suggestion)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct RefactoringProgressHeader: View {
    let progress: Double
    let operation: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Smart Refactoring Analysis")
                    .font(.headline)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())

            HStack {
                Text(operation)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct EmptyRefactoringState: View {
    let hasAnalyzed: Bool
    let onAnalyze: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: hasAnalyzed ? "checkmark.circle.fill" : "wand.and.stars")
                .font(.system(size: 60))
                .foregroundColor(hasAnalyzed ? .green : .blue)

            Text(hasAnalyzed ? "Excellent Work!" : "Smart Refactoring")
                .font(.title)
                .fontWeight(.semibold)

            Text(hasAnalyzed ?
                 "Your project structure is already well-organized! No refactoring suggestions needed." :
                 "Automatically organize your i18n keys based on SvelteKit route patterns")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if hasAnalyzed {
                // Congratulatory content
                VStack(alignment: .leading, spacing: 8) {
                    CongratulationRow(
                        icon: "checkmark.seal.fill",
                        title: "Keys Well-Organized",
                        description: "Your translation keys follow good patterns"
                    )

                    CongratulationRow(
                        icon: "folder.fill.badge.checkmark",
                        title: "Route Structure Clean",
                        description: "No namespace improvements needed"
                    )

                    CongratulationRow(
                        icon: "sparkles",
                        title: "Project Optimized",
                        description: "Your i18n setup is in great shape"
                    )
                }
                .padding(.horizontal, 40)

                Button("Analyze Again") {
                    onAnalyze()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                // Initial state content
                VStack(alignment: .leading, spacing: 8) {
                    RefactoringFeatureRow(
                        icon: "folder.badge.gearshape",
                        title: "Route-based Nesting",
                        description: "Organize keys by file location"
                    )

                    RefactoringFeatureRow(
                        icon: "arrow.triangle.branch",
                        title: "Smart Suggestions",
                        description: "AI-powered key restructuring"
                    )

                    RefactoringFeatureRow(
                        icon: "checkmark.circle",
                        title: "Safe Refactoring",
                        description: "Preview changes before applying"
                    )
                }
                .padding(.horizontal, 40)

                Button("Analyze Project") {
                    onAnalyze()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RefactoringFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct CongratulationRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

struct SmartRefactoringView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let project = Project(context: context)
        project.name = "Test Project"
        project.path = "/path/to/project"

        return SmartRefactoringView(project: project)
    }
}
