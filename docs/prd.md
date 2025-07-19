SvelteKit-focused i18n JSON editor macOS app with a clean, Apple Human Interface Guidelines-compliant UI.

## Core Application Purpose
Build a macOS application that streamlines internationalization (i18n) management for SvelteKit projects by automatically detecting i18n usage, parsing configuration files, and providing an intuitive editing interface.

## Technical Requirements & Features

### 1. Project Management
- **Folder Selection**: Allow users to open and select a SvelteKit project folder as their workspace
- **Project Persistence**: Remember recently opened projects for quick access

### 2. Automated i18n Detection & Analysis
- **File Scanning**: Recursively scan all `*.svelte` files within the `src/` directory
- **Pattern Matching**: Detect i18n function calls using the pattern `m.xxxxxx()` (where `xxxxxx` represents the i18n key)
- **Usage Tracking**: For each detected i18n key, record:
  - The key name
  - Array of file paths where the key is used
  - Line numbers and context (optional enhancement)

### 3. Data Storage & Caching
- **Local Database**: Implement SQLite3 or similar lightweight database for fast data persistence
- **Schema Design**: Store detected keys, file usage mappings, and user edits
- **Performance**: Optimize for quick retrieval and real-time updates
- **Dependency Management**: Request user approval before installing any required libraries

### 4. Inlang Configuration Integration
- **Settings Discovery**: Locate and parse `project.inlang/settings.json` configuration file
- **Configuration Schema**: Support the standard inlang project settings format including:
  - `baseLocale`: Primary language (e.g., "zh-HK")
  - `locales`: Array of supported languages (e.g., ["en", "de", "zh-HK"])
  - `modules`: Plugin configurations
  - `plugin.inlang.messageFormat.pathPattern`: Path template for locale files (e.g., "./messages/{locale}.json")

### 5. Locale File Management
- **Dynamic File Discovery**: Use pathPattern to locate locale-specific JSON files
- **Multi-format Support**: Handle both flat and nested key structures:
  - Flat: `{"welcome": "Welcome!"}`
  - Nested: `{"home": {"welcome": "Welcome!"}}`
- **Schema Validation**: Support inlang message format schema

### 6. Intelligent Key Refactoring (Advanced Feature)
- **Route-based Organization**: Analyze SvelteKit's file-based routing structure (`src/routes/*`)
- **Auto-refactoring Proposal**: Suggest reorganizing i18n keys using route-based prefixes
  - Example: Convert `welcome` → `home.welcome` for keys used in `/src/routes/`
  - Example 2: Convert `welcome` → `articles.welcome` for keys used in `/src/routes/articles`
- **User Control**: Make this feature entirely optional with clear preview and approval workflow

### 7. User Interface Requirements
- **Design System**: Strictly adhere to Apple Human Interface Guidelines
- **Clean & Minimal**: Prioritize clarity and ease of use over feature density
- **Responsive Layout**: Ensure usability across different screen sizes

### 8. Translation Editor Interface
- **Table-based Layout**:
  - First column: i18n keys
  - Subsequent columns: One per configured locale
  - One row per translation key
- **Hierarchical Display**: Group nested keys under collapsible sub-headings
- **Inline Editing**: Allow direct editing of translation values within table cells
- **Auto-save Draft**: Automatically save changes to local database as drafts
- **Explicit Save**: Provide clear "Save to Files" button to commit changes to actual JSON files
- **Change Indicators**: Visual feedback for unsaved changes and draft status

### 9. Additional UX Considerations
- **Search & Filter**: Enable quick key lookup and filtering
- **Validation**: Highlight missing translations or formatting issues
- **Backup & Recovery**: Protect against data loss during editing
- **Performance**: Ensure smooth experience even with large translation sets

## Success Criteria
- Seamless integration with existing SvelteKit + inlang workflows
- Significant reduction in time spent managing i18n files manually
- Intuitive interface that requires minimal learning curve
- Reliable detection of all i18n usage without false positives
- Safe editing environment with robust draft/save mechanisms