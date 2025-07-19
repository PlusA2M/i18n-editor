//
//  UsageTrackingTestView.swift
//  i18n editor
//
//  Created by PlusA on 18/07/2025.
//

import SwiftUI

/// View for running and displaying usage tracking integration tests
struct UsageTrackingTestView: View {
    @StateObject private var integrationTest = UsageTrackingIntegrationTest()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with progress
                if integrationTest.isRunning {
                    TestProgressHeader(
                        progress: integrationTest.testProgress,
                        currentTest: integrationTest.currentTest
                    )
                }
                
                // Test results
                TestResultsView(results: integrationTest.testResults)
                
                // Action buttons
                HStack {
                    Button("Clear Results") {
                        integrationTest.testResults.removeAll()
                    }
                    .disabled(integrationTest.isRunning)
                    
                    Spacer()
                    
                    Button("Export Results") {
                        exportTestResults()
                    }
                    .disabled(integrationTest.testResults.isEmpty)
                    
                    Button("Run Integration Test") {
                        Task {
                            await integrationTest.runIntegrationTest()
                        }
                    }
                    .disabled(integrationTest.isRunning)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Usage Tracking Integration Test")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private func exportTestResults() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "usage-tracking-test-results-\(Date().timeIntervalSince1970).txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let resultsContent = integrationTest.testResults.map { result in
                    let timestamp = DateFormatter.testTimestamp.string(from: result.timestamp)
                    let status = result.success ? "PASS" : "FAIL"
                    return "[\(timestamp)] \(status): \(result.testName) - \(result.message)"
                }.joined(separator: "\n")
                
                try? resultsContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct TestProgressHeader: View {
    let progress: Double
    let currentTest: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "testtube.2")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Running Integration Tests")
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                
                Text(currentTest)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

struct TestResultsView: View {
    let results: [TestResult]
    
    var body: some View {
        List {
            ForEach(results) { result in
                TestResultRow(result: result)
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct TestResultRow: View {
    let result: TestResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
                .font(.body)
                .frame(width: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.testName)
                        .font(.headline)
                        .foregroundColor(result.success ? .primary : .red)
                    
                    Spacer()
                    
                    Text(DateFormatter.testTime.string(from: result.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(result.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let testTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    static let testTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

// MARK: - Preview

struct UsageTrackingTestView_Previews: PreviewProvider {
    static var previews: some View {
        UsageTrackingTestView()
    }
}
