//
//  SmartRefactoringView.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI

struct SmartRefactoringView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var isRefactoring = false
    @State private var refactoringProgress: Double = 0.0
    @State private var refactoringStatus = "Ready to start"
    @State private var refactoringResults: RefactoringResults?
    @State private var selectedOptions: Set<RefactoringOption> = [.sortKeys, .removeEmpty, .formatJSON]

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            HStack {
                Text("Smart Refactoring")
                    .font(.title)
                    .fontWeight(.semibold)

                Spacer()

                Button("✕") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.title2)
                .foregroundColor(.secondary)
                .help("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Main content in scroll view
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Section
                    HeaderSection()

                    // Options Section
                    OptionsSection(
                        selectedOptions: $selectedOptions,
                        isRefactoring: isRefactoring
                    )

                    // Progress Section (always present to avoid layout jumps)
                    ProgressSection(
                        isRefactoring: isRefactoring,
                        progress: refactoringProgress,
                        status: refactoringStatus
                    )

                    // Results Section
                    if let results = refactoringResults {
                        ResultsSection(results: results)
                    }

                    // Action Buttons
                    ActionButtonsSection(
                        isRefactoring: isRefactoring,
                        hasSelectedOptions: !selectedOptions.isEmpty,
                        onCancel: { dismiss() },
                        onStartRefactoring: startRefactoring
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 700, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func startRefactoring() {
        isRefactoring = true
        refactoringProgress = 0.0
        refactoringStatus = "Initializing..."
        refactoringResults = nil
        
        Task {
            await performRefactoring()
        }
    }
    
    private func performRefactoring() async {
        let refactorer = SmartRefactorer()
        
        do {
            let results = await refactorer.refactorProject(
                project: project,
                options: selectedOptions,
                progressCallback: { progress, status in
                    DispatchQueue.main.async {
                        self.refactoringProgress = progress
                        self.refactoringStatus = status
                    }
                }
            )
            
            DispatchQueue.main.async {
                self.refactoringResults = results
                self.isRefactoring = false
                self.refactoringStatus = "Completed"
            }
            
        } catch {
            DispatchQueue.main.async {
                var errorMessage = "Refactoring failed: \(error.localizedDescription)"

                // Provide specific guidance for permission errors
                if error.localizedDescription.contains("permission") ||
                   error.localizedDescription.contains("access") ||
                   (error as NSError).domain == "SmartRefactorerError" {
                    errorMessage += "\n\nTo fix this issue:\n1. Close this dialog\n2. Go to File > Open Project\n3. Select your project folder again to grant write permissions\n4. Try Smart Refactoring again"
                }

                self.refactoringResults = RefactoringResults(
                    filesProcessed: 0,
                    keysReorganized: 0,
                    emptyKeysRemoved: 0,
                    duplicatesMerged: 0,
                    errors: [errorMessage]
                )
                self.isRefactoring = false
                self.refactoringStatus = "Failed"
            }
        }
    }
}

// MARK: - Section Components

struct HeaderSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatically reorganize and optimize your translation files")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text("Select the refactoring options you want to apply to your project.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct OptionsSection: View {
    @Binding var selectedOptions: Set<RefactoringOption>
    let isRefactoring: Bool

    private let fileOperations: [RefactoringOption] = [.formatJSON, .sortKeys]
    private let contentOperations: [RefactoringOption] = [.removeEmpty, .mergeDuplicates, .optimizeNesting]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Refactoring Options")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 20) {
                OptionGroup(
                    title: "File Operations",
                    icon: "doc.text",
                    options: fileOperations,
                    selectedOptions: $selectedOptions,
                    isDisabled: isRefactoring
                )

                OptionGroup(
                    title: "Content Operations",
                    icon: "text.alignleft",
                    options: contentOperations,
                    selectedOptions: $selectedOptions,
                    isDisabled: isRefactoring
                )
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct OptionGroup: View {
    let title: String
    let icon: String
    let options: [RefactoringOption]
    @Binding var selectedOptions: Set<RefactoringOption>
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    OptionRow(
                        option: option,
                        isSelected: selectedOptions.contains(option),
                        isDisabled: isDisabled
                    ) { isSelected in
                        if isSelected {
                            selectedOptions.insert(option)
                        } else {
                            selectedOptions.remove(option)
                        }
                    }
                }
            }
            .padding(.leading, 24)
        }
    }
}

struct OptionRow: View {
    let option: RefactoringOption
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: onToggle
            ))
            .toggleStyle(CheckboxToggleStyle())
            .disabled(isDisabled)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.body)
                    .foregroundColor(isDisabled ? .secondary : .primary)

                Text(option.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled {
                onToggle(!isSelected)
            }
        }
    }
}

struct ProgressSection: View {
    let isRefactoring: Bool
    let progress: Double
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: isRefactoring ? "gearshape.2" : "checkmark.circle")
                    .foregroundColor(isRefactoring ? .blue : .green)
                    .font(.title2)

                Text("Progress")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if isRefactoring {
                    Text("\(Int(progress * 100))%")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }

            if isRefactoring {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(y: 1.5)

                    Text(status)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Ready to start refactoring")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.3), value: isRefactoring)
    }
}

struct ResultsSection: View {
    let results: RefactoringResults

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: results.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(results.errors.isEmpty ? .green : .orange)
                    .font(.title2)

                Text("Results")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }

            // Statistics Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                StatisticCard(
                    title: "Files Processed",
                    value: "\(results.filesProcessed)",
                    icon: "doc.text",
                    color: .blue
                )

                StatisticCard(
                    title: "Keys Reorganized",
                    value: "\(results.keysReorganized)",
                    icon: "arrow.up.arrow.down",
                    color: .green
                )

                StatisticCard(
                    title: "Empty Keys Removed",
                    value: "\(results.emptyKeysRemoved)",
                    icon: "trash",
                    color: .orange
                )

                StatisticCard(
                    title: "Duplicates Merged",
                    value: "\(results.duplicatesMerged)",
                    icon: "arrow.triangle.merge",
                    color: .purple
                )
            }

            // Errors Section
            if !results.errors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Errors")
                            .font(.headline)
                            .foregroundColor(.red)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(results.errors, id: \.self) { error in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ActionButtonsSection: View {
    let isRefactoring: Bool
    let hasSelectedOptions: Bool
    let onCancel: () -> Void
    let onStartRefactoring: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                onCancel()
            }
            .disabled(isRefactoring)
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button(isRefactoring ? "Refactoring..." : "Start Refactoring") {
                onStartRefactoring()
            }
            .disabled(isRefactoring || !hasSelectedOptions)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.top, 8)
    }
}

// Custom Toggle Style for better checkbox appearance
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .blue : .secondary)
                .font(.system(size: 16))
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
        }
    }
}

// MARK: - Supporting Types

enum RefactoringOption: String, CaseIterable {
    case sortKeys = "sort_keys"
    case removeEmpty = "remove_empty"
    case formatJSON = "format_json"
    case mergeDuplicates = "merge_duplicates"
    case optimizeNesting = "optimize_nesting"
    
    var title: String {
        switch self {
        case .sortKeys:
            return "Sort Keys Alphabetically"
        case .removeEmpty:
            return "Remove Empty Translations"
        case .formatJSON:
            return "Format JSON Files"
        case .mergeDuplicates:
            return "Merge Duplicate Keys"
        case .optimizeNesting:
            return "Optimize Key Nesting"
        }
    }
    
    var description: String {
        switch self {
        case .sortKeys:
            return "Sort all translation keys in alphabetical order"
        case .removeEmpty:
            return "Remove keys with empty or null values"
        case .formatJSON:
            return "Format JSON files with consistent indentation"
        case .mergeDuplicates:
            return "Merge duplicate keys and resolve conflicts"
        case .optimizeNesting:
            return "Optimize nested key structure for better organization"
        }
    }
}

struct RefactoringResults {
    let filesProcessed: Int
    let keysReorganized: Int
    let emptyKeysRemoved: Int
    let duplicatesMerged: Int
    let errors: [String]
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let project = Project(context: context)
    project.name = "Sample Project"
    project.path = "/path/to/project"
    project.baseLocale = "en"
    project.locales = ["en", "fr", "de"]
    project.pathPattern = "./messages/{locale}.json"
    
    return SmartRefactoringView(project: project)
}
