# Usage Tracking Improvements

This document outlines the comprehensive improvements made to the i18n editor's usage tracking functionality to fix the non-functional translation key detection system.

## Issues Identified

1. **Insufficient Regex Patterns**: The original regex patterns were too restrictive and missed many common usage patterns
2. **Limited Error Handling**: No comprehensive error reporting or debugging capabilities
3. **Permission Issues**: Inadequate handling of macOS sandbox permissions
4. **No Diagnostic Tools**: No way to debug why usage tracking wasn't working
5. **Missing Initial Extraction**: Usage tracking never triggered initial scan when project loaded, leaving database empty

## Improvements Made

### 1. Enhanced Regex Patterns

**File**: `SvelteFileScanner.swift`

Replaced the original 6 basic patterns with 10 comprehensive patterns that cover:

- Function calls with and without parameters: `m.key()`, `m.key(params)`
- Nested keys: `m.nested.key.name()`
- Reactive statements: `$m.reactive`
- Template expressions: `{m.template()}`, `{ m.spaced }`
- Direct property access: `m.property`
- Quoted strings: `"m.dynamicKey"`
- Bracket notation: `m['bracketKey']`
- Whitespace handling: Patterns now handle optional whitespace

### 2. Comprehensive Debug Logging

**Files**: `UsageTrackingDebugger.swift`, `SvelteFileScanner.swift`, `FileSystemManager.swift`, `UsageTrackingSystem.swift`, `I18nKeyExtractor.swift`

Added detailed logging throughout the entire pipeline:

- File scanning progress and results
- Pattern matching attempts and results
- Permission errors and file access failures
- Performance metrics and timing
- Database operations and results

### 3. Permission Diagnostics

**File**: `UsageTrackingDebugger.swift`

Enhanced permission checking:

- Full Disk Access verification
- Security-scoped bookmark validation
- Project directory access testing
- File enumeration testing
- Detailed permission error reporting

### 4. Debug UI Components

**Files**: `UsageTrackingDebugView.swift`, `UsageTrackingTestView.swift`

Created comprehensive debugging interfaces:

- Real-time debug log viewer
- Pattern testing with sample inputs
- File scanning diagnostics
- Permission status indicators
- Integration test runner

### 5. Integration Testing

**File**: `UsageTrackingIntegrationTest.swift`

Comprehensive test suite that:

- Creates test project structures
- Tests file system permissions
- Validates regex pattern matching
- Tests database operations
- Verifies complete pipeline functionality

### 6. Enhanced Status Indicators

**File**: `TranslationEditorView.swift`

Improved UI feedback:

- Real-time tracking status indicator
- Error message display
- Detailed usage statistics
- Last update timestamps

### 7. Fixed Initial Extraction

**File**: `UsageTrackingSystem.swift`

Critical fix for the main issue:

- **Added initial extraction** when usage tracking starts
- **Force rescan functionality** for manual refresh
- **Proper database population** on project load
- **Async extraction** to avoid blocking UI

## How to Use the Improvements

### 1. Access Debug Tools

1. Open any project in the i18n editor
2. Click the "Debug Usage" button in the toolbar
3. Run "Debug Analysis" to diagnose issues
4. Use "Integration Test" to run comprehensive tests

### 2. Interpret Debug Results

- **Green indicators**: Functionality working correctly
- **Orange warnings**: Potential issues that may affect performance
- **Red errors**: Critical issues preventing functionality

### 3. Common Issues and Solutions

#### No Svelte Files Found
- **Cause**: Permission issues or incorrect project structure
- **Solution**: Grant Full Disk Access or ensure project has `src/` directory

#### No Key Usages Detected
- **Cause**: Regex patterns not matching your usage style
- **Solution**: Check pattern test results and verify your code uses `m.key()` format

#### Database Errors
- **Cause**: Core Data issues or permission problems
- **Solution**: Check file write permissions and database integrity

## Technical Details

### Regex Pattern Examples

The improved patterns now match these usage styles:

```javascript
// Function calls
m.hello()
m.nested.key()
m.withParams({name: 'test'})

// Reactive statements
$m.reactive
$m.nested.reactive

// Template expressions
{m.template()}
{ m.spaced }
{m.withParams(data)}

// Direct access
const text = m.assignment
if (condition) m.conditional

// Dynamic access
const key = 'm.dynamicKey'
m['bracketKey']
```

### Performance Improvements

- Added scan statistics tracking
- Implemented progress reporting
- Added timing measurements
- Optimized file processing

### Error Recovery

- Graceful handling of permission errors
- Continued processing despite individual file failures
- Comprehensive error reporting
- Automatic retry mechanisms

## Testing

Run the integration test to verify all improvements:

1. Open Debug Usage view
2. Click "Integration Test"
3. Click "Run Integration Test"
4. Review results for any failures

The test creates a temporary project structure and validates the entire usage tracking pipeline.

## Future Enhancements

Potential areas for further improvement:

1. **TypeScript Support**: Add patterns for TypeScript usage
2. **Custom Pattern Configuration**: Allow users to define custom regex patterns
3. **Performance Optimization**: Implement file watching for incremental updates
4. **Advanced Analytics**: Add usage trend analysis and reporting
5. **Multi-language Support**: Extend beyond Svelte to other frameworks
