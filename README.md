# 🌍 i18n Editor for macOS

> **A beautiful, native macOS app for effortless Paraglide JS internationalization management**

Transform your Paraglide JS workflow with an intuitive, Apple Human Interface Guidelines-compliant editor that makes managing i18n JSON files a breeze. Optimized for SvelteKit projects using Paraglide JS from inlang.

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0066CC?style=for-the-badge&logo=swift&logoColor=white)
![Paraglide JS](https://img.shields.io/badge/Paraglide_JS-00D4AA?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDJMMTMuMDkgOC4yNkwyMCA5TDEzLjA5IDE1Ljc0TDEyIDIyTDEwLjkxIDE1Ljc0TDQgOUwxMC45MSA4LjI2TDEyIDJaIiBmaWxsPSJ3aGl0ZSIvPgo8L3N2Zz4K&logoColor=white)

## ✨ Why i18n Editor?

**Stop wrestling with JSON files.** Start focusing on what matters - your content.

- 🎯 **Native macOS Experience** - Feels right at home on your Mac
- 🚀 **Paraglide JS Optimized** - Built specifically for Paraglide JS workflows
- 🔍 **Smart Detection** - Automatically scans `project.inlang/settings.json` and i18n JSON files
- 📊 **Visual Translation Table** - Spreadsheet-like editing with Excel-style navigation
- 🧠 **Intelligent Refactoring** - AI-powered optimization suggestions
- ⚡ **Real-time Validation** - Catch issues before they reach production
- 🌐 **Framework Agnostic** - Works with any framework using similar inlang settings

## 🎬 Features That Make You Smile

### 📝 **Intuitive Translation Editing**
- **Double-click to edit** any translation cell
- **Arrow key navigation** between cells (just like Excel!)
- **Tab/Shift+Tab** for sequential editing
- **Auto-save drafts** with visual change indicators
- **Bulk operations** for efficient mass editing

### 🔧 **Smart Refactoring Engine**
- **Remove empty translations** automatically
- **Merge duplicate keys** with conflict resolution
- **Optimize nesting structure** for better organization
- **Sort keys alphabetically** for consistency
- **Format JSON** with beautiful indentation

### 🔍 **Advanced Search & Filtering**
- **Real-time search** across all translations
- **Filter by status** (missing, empty, complete)
- **Sort by usage frequency** or alphabetically
- **Multi-locale filtering** for targeted editing

### 📊 **Project Intelligence**
- **Automatic settings detection** - Scans `project.inlang/settings.json` automatically
- **Usage tracking** - See which keys are actually used in your codebase
- **Translation statistics** with completion percentages
- **Route-based analysis** for SvelteKit + Paraglide JS projects
- **Smart key extraction** from Svelte files and Paraglide JS usage patterns

### ⚡ **Validation & Quality Assurance**
- **Real-time validation** of message formats
- **Cross-locale consistency checks**
- **Missing translation detection**
- **Syntax error highlighting**
- **Auto-fix suggestions** for common issues

### 🗂️ **Seamless Project Management**
- **Automatic inlang project detection** - Finds and loads `project.inlang/settings.json`
- **Paraglide JS configuration support** - Reads pathPattern, locales, and baseLocale
- **Automatic locale file creation** when adding new languages
- **Smart file deletion prompts** when removing locales
- **Security-scoped file access** (macOS sandbox compliant)
- **Recent projects** for quick access

## 🚀 Getting Started

### Prerequisites
- macOS 12.0 or later
- A project with Paraglide JS setup (SvelteKit recommended)
- `project.inlang/settings.json` configuration file

### Installation
1. Download the latest release from [Releases](../../releases)
2. Drag **i18n Editor.app** to your Applications folder
3. Launch and grant file access permissions when prompted

### First Steps
1. **Open your project** - Click "Select Project Folder" and choose your project root
2. **Automatic detection** - The app scans for `project.inlang/settings.json` and loads your configuration
3. **Start editing** - Double-click any cell to begin translating
4. **Save when ready** - Hit "Save All" to write changes to your JSON files

### Supported Project Structure
```
your-project/
├── project.inlang/
│   └── settings.json          # Paraglide JS configuration
├── messages/                  # Translation files (configurable path)
│   ├── en.json
│   ├── de.json
│   └── fr.json
└── src/                       # Your source code
```

### Framework Compatibility
While optimized for **Paraglide JS + SvelteKit**, this app works with any project that uses:
- `project.inlang/settings.json` configuration file
- JSON-based translation files
- Standard inlang pathPattern structure

**Tested with:**
- ✅ SvelteKit + Paraglide JS
- ✅ Next.js + Paraglide JS
- ✅ Astro + Paraglide JS
- ✅ Any framework following inlang conventions

## 🎯 Perfect For

- **Paraglide JS users** in SvelteKit projects seeking visual translation management
- **inlang ecosystem adopters** who want a native macOS editing experience
- **Translation teams** who prefer spreadsheet-like editing over raw JSON
- **Project managers** tracking translation progress across multiple locales
- **Developers using any framework** with similar `project.inlang/settings.json` structure
- **Anyone** tired of manually editing JSON translation files

## 🛠️ Built With Love Using

- **SwiftUI** - For that native macOS feel
- **Core Data** - Robust data persistence
- **Security-Scoped Bookmarks** - Sandbox-friendly file access
- **Combine** - Reactive programming patterns
- **inlang ecosystem integration** - Native support for Paraglide JS workflows
- **Apple Human Interface Guidelines** - Because good design matters

## 🤝 Contributing & Feature Requests

We'd love to hear from you! This app is built for the community, by the community.

### 💡 Request Features
Have an idea that would make your i18n workflow even better? 
[Open an issue](../../issues/new) and tell us about it!

### 🐛 Found a Bug?
Help us squash it! [Report bugs here](../../issues/new) with:
- Steps to reproduce
- Expected vs actual behavior
- Your macOS version
- Sample project (if possible)

### 🔧 Want to Contribute?
1. Fork the repository
2. Create a feature branch (`git checkout -b amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- The **inlang team** for creating Paraglide JS and the amazing i18n ecosystem
- The **SvelteKit team** for building an incredible framework
- The **i18n community** for inspiration and feedback
- **Apple** for the excellent development tools and guidelines

---

**Made with ❤️ for the Paraglide JS and SvelteKit community**

*Transform your translation workflow today - because life's too short for manual JSON editing.*
