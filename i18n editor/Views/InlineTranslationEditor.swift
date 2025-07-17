//
//  InlineTranslationEditor.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import SwiftUI
import Combine

/// Inline editing system for translation values with auto-save drafts and validation
struct InlineTranslationEditor: View {
    let key: I18nKey
    let locale: String
    let isSelected: Bool

    @State private var isEditing = false
    @State private var editingValue = ""
    @State private var originalValue = ""
    @State private var hasUnsavedChanges = false
    @State private var validationResult: InlineTranslationValidationResult?
    @State private var showingValidationPopover = false
    @State private var autoSaveTimer: Timer?

    @StateObject private var dataManager = DataManager.shared
    @StateObject private var validator = MessageFormatValidator()

    private let autoSaveDelay: TimeInterval = 2.0 // Auto-save after 2 seconds of inactivity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditing {
                editingView
            } else {
                displayView
            }

            // Validation indicator
            if let validation = validationResult, validation.hasIssues {
                validationIndicator
            }
        }
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            loadInitialValue()
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Text editor
            TextEditor(text: $editingValue)
                .font(.system(.body, design: .default))
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(hasUnsavedChanges ? Color.orange : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .frame(minHeight: 60, maxHeight: 120)
                .onChange(of: editingValue) { newValue in
                    handleValueChange(newValue)
                }
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.command) {
                        commitChanges()
                    }
                }

            // Editing controls
            HStack {
                // Character count
                Text("\(editingValue.count) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                // Auto-save indicator
                if hasUnsavedChanges {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Auto-saving...")
                            .font(.caption2)
                    }
                    .foregroundColor(.orange)
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.escape)

                    Button("Save") {
                        commitChanges()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(editingValue == originalValue)
                }
            }
            .font(.caption)
        }
    }

    private var displayView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                // Translation value
                Text(displayValue)
                    .foregroundColor(displayValueColor)
                    .italic(displayValue.isEmpty || displayValue == "Missing")
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Status indicators
                if let translation = translation {
                    HStack(spacing: 8) {
                        if translation.isDraft {
                            Label("Draft", systemImage: "pencil.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }

                        if translation.hasChanges {
                            Label("Modified", systemImage: "circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }

                        if let lastModified = translation.lastModified {
                            Text(lastModified, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // Status icons
            VStack(spacing: 2) {
                if translation?.isDraft == true {
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .help("Draft changes")
                }

                if let validation = validationResult, validation.hasIssues {
                    Button(action: { showingValidationPopover = true }) {
                        Image(systemName: validation.hasErrors ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(validation.hasErrors ? .red : .yellow)
                    }
                    .buttonStyle(.plain)
                    .help("Validation issues")
                    .popover(isPresented: $showingValidationPopover) {
                        ValidationPopoverView(result: validation)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            startEditing()
        }
        .contextMenu {
            contextMenu
        }
    }

    private var contextMenu: some View {
        VStack {
            Button("Edit") {
                startEditing()
            }

            if translation?.isDraft == true {
                Button("Commit Draft") {
                    commitDraft()
                }
            }

            if !(translation?.value?.isEmpty ?? true) {
                Button("Clear") {
                    clearTranslation()
                }
            }

            Divider()

            Button("Copy") {
                copyToClipboard()
            }

            Button("Paste") {
                pasteFromClipboard()
            }
        }
    }

    private var validationIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: validationResult?.hasErrors == true ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.caption2)
                .foregroundColor(validationResult?.hasErrors == true ? .red : .yellow)

            Text("\(validationResult?.issues.count ?? 0) issue(s)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Computed Properties

    private var translation: Translation? {
        key.translation(for: locale)
    }

    private var displayValue: String {
        if let translation = translation {
            let value = translation.effectiveValue ?? ""
            return value.isEmpty ? "Empty" : value
        }
        return "Missing"
    }

    private var displayValueColor: Color {
        if let translation = translation {
            let value = translation.effectiveValue ?? ""
            return value.isEmpty ? .secondary : .primary
        }
        return .secondary
    }

    // MARK: - Editing Actions

    private func startEditing() {
        loadInitialValue()
        isEditing = true

        // Focus on the text editor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Text editor will be focused automatically
        }
    }

    private func cancelEditing() {
        editingValue = originalValue
        hasUnsavedChanges = false
        isEditing = false
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    private func commitChanges() {
        saveDraft()
        isEditing = false
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    private func handleValueChange(_ newValue: String) {
        hasUnsavedChanges = newValue != originalValue

        // Validate the new value
        validateValue(newValue)

        // Reset auto-save timer
        autoSaveTimer?.invalidate()

        if hasUnsavedChanges {
            autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { _ in
                saveDraft()
            }
        }
    }

    private func saveDraft() {
        guard hasUnsavedChanges else { return }

        _ = dataManager.createOrUpdateTranslation(
            i18nKey: key,
            locale: locale,
            value: editingValue,
            isDraft: true
        )

        hasUnsavedChanges = false
    }

    private func commitDraft() {
        guard let translation = translation else { return }

        _ = dataManager.createOrUpdateTranslation(
            i18nKey: key,
            locale: locale,
            value: translation.draftValue,
            isDraft: false
        )
    }

    private func clearTranslation() {
        _ = dataManager.createOrUpdateTranslation(
            i18nKey: key,
            locale: locale,
            value: "",
            isDraft: true
        )
    }

    private func loadInitialValue() {
        originalValue = translation?.effectiveValue ?? ""
        editingValue = originalValue
        hasUnsavedChanges = false

        // Validate initial value
        validateValue(originalValue)
    }

    private func validateValue(_ value: String) {
        let result = validator.validateMessage(value, key: key.key ?? "", locale: locale)

        validationResult = InlineTranslationValidationResult(
            hasErrors: result.issues.contains { $0.severity == .error },
            hasWarnings: result.issues.contains { $0.severity == .warning },
            issues: result.issues.map { issue in
                InlineTranslationValidationIssue(
                    type: issue.type,
                    severity: issue.severity,
                    message: issue.message,
                    suggestion: issue.suggestion
                )
            }
        )
    }

    // MARK: - Clipboard Operations

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayValue, forType: .string)
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            editingValue = string
            startEditing()
        }
    }
}

struct ValidationPopoverView: View {
    let result: InlineTranslationValidationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Validation Issues")
                .font(.headline)

            ForEach(result.issues, id: \.id) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .foregroundColor(issue.severity == .error ? .red : .yellow)

                        Text(issue.message)
                            .font(.body)
                    }

                    if !issue.suggestion.isEmpty {
                        Text(issue.suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }

                if issue.id != result.issues.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .frame(maxWidth: 300)
    }
}

// MARK: - Supporting Types

struct InlineTranslationValidationResult {
    let hasErrors: Bool
    let hasWarnings: Bool
    let issues: [InlineTranslationValidationIssue]

    var hasIssues: Bool {
        return !issues.isEmpty
    }
}

struct InlineTranslationValidationIssue: Identifiable {
    let id = UUID()
    let type: IssueType
    let severity: IssueSeverity
    let message: String
    let suggestion: String
}

// MARK: - Keyboard Shortcuts

struct TranslationEditorKeyboardShortcuts: View {
    let onSave: () -> Void
    let onCancel: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack {
            // Invisible buttons to handle keyboard shortcuts
            Button("Save", action: onSave)
                .keyboardShortcut("s", modifiers: .command)
                .hidden()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape)
                .hidden()

            Button("Edit", action: onEdit)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .hidden()
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

#Preview {
    // Create a mock key and translation for preview
    let context = PersistenceController.preview.container.viewContext
    let project = Project(context: context)
    project.locales = ["en", "es"]

    let key = I18nKey(context: context)
    key.key = "welcome.message"
    key.project = project

    let translation = Translation(context: context)
    translation.locale = "en"
    translation.value = "Welcome to our application!"
    translation.i18nKey = key
    translation.project = project

    return InlineTranslationEditor(
        key: key,
        locale: "en",
        isSelected: false
    )
    .frame(width: 300, height: 100)
    .padding()
}
