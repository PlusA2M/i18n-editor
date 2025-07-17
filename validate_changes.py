#!/usr/bin/env python3
"""
Simple validation script to check for basic syntax issues in our Swift changes.
"""

import os
import re
import sys

def check_swift_file(filepath):
    """Check a Swift file for basic syntax issues."""
    issues = []
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        lines = content.split('\n')
    
    # Check for basic syntax issues
    brace_count = 0
    paren_count = 0
    bracket_count = 0
    
    for i, line in enumerate(lines, 1):
        # Count braces, parentheses, brackets
        brace_count += line.count('{') - line.count('}')
        paren_count += line.count('(') - line.count(')')
        bracket_count += line.count('[') - line.count(']')
        
        # Check for common issues
        if 'DispatchQueue.main.async' in line and '{' not in line and i < len(lines):
            # Check if next line has opening brace
            next_line = lines[i] if i < len(lines) else ""
            if '{' not in next_line:
                issues.append(f"Line {i}: DispatchQueue.main.async might be missing opening brace")
        
        # Check for incomplete function definitions
        if re.match(r'\s*func\s+\w+.*\{\s*$', line):
            # Function with empty body - might be incomplete
            if i < len(lines) and lines[i].strip() == '}':
                issues.append(f"Line {i}: Function appears to have empty body")
    
    # Check final counts
    if brace_count != 0:
        issues.append(f"Mismatched braces: {brace_count} extra opening braces")
    if paren_count != 0:
        issues.append(f"Mismatched parentheses: {paren_count} extra opening parentheses")
    if bracket_count != 0:
        issues.append(f"Mismatched brackets: {bracket_count} extra opening brackets")
    
    return issues

def main():
    """Main validation function."""
    print("🔍 Validating Swift code changes...")
    
    # Files we've modified
    modified_files = [
        "i18n editor/Views/TranslationEditorView.swift",
        "i18n editor/PermissionManager.swift",
        "i18n editor/FileSystemManager.swift",
        "i18n editor/i18n_editorApp.swift",
        "i18n editor/ContentView.swift",
        "i18n editor/ProjectManager.swift"
    ]
    
    total_issues = 0
    
    for filepath in modified_files:
        if os.path.exists(filepath):
            print(f"\n📄 Checking {filepath}...")
            issues = check_swift_file(filepath)
            
            if issues:
                print(f"  ❌ Found {len(issues)} issues:")
                for issue in issues:
                    print(f"    • {issue}")
                total_issues += len(issues)
            else:
                print(f"  ✅ No syntax issues found")
        else:
            print(f"  ⚠️  File not found: {filepath}")
    
    print(f"\n📊 Validation Summary:")
    print(f"  • Files checked: {len([f for f in modified_files if os.path.exists(f)])}")
    print(f"  • Total issues: {total_issues}")
    
    if total_issues == 0:
        print("  🎉 All files passed basic syntax validation!")
        return 0
    else:
        print("  ⚠️  Some issues found - please review")
        return 1

if __name__ == "__main__":
    sys.exit(main())
