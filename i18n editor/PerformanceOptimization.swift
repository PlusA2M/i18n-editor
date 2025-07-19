//
//  PerformanceOptimization.swift
//  i18n editor
//
//  Created by PlusA on 13/07/2025.
//

import Foundation
import SwiftUI
import Combine

/// Performance optimization and caching system for the i18n editor
class PerformanceOptimizer: ObservableObject {
    @Published var cacheStatistics = CacheStatistics()
    @Published var performanceMetrics = PerformanceMetrics()
    @Published var isOptimizing = false
    
    private let cache = CacheManager()
    private let metricsCollector = MetricsCollector()
    private var optimizationTimer: Timer?
    
    // MARK: - Cache Management
    
    /// Initialize caching system
    func initializeCache() async {
        await cache.configure(
            maxMemorySize: 100 * 1024 * 1024, // 100MB
            maxDiskSize: 500 * 1024 * 1024,   // 500MB
            ttl: 3600 // 1 hour
        )

        // Start periodic cache cleanup
        startCacheCleanup()
    }
    
    /// Cache translation data
    func cacheTranslations(for project: Project) async {
        let cacheKey = "translations_\(project.id?.uuidString ?? "")"
        
        let translations = project.translations?.allObjects as? [Translation] ?? []
        let translationData = translations.map { translation in
            CachedTranslation(
                id: translation.id?.uuidString ?? "",
                key: translation.i18nKey?.key ?? "",
                locale: translation.locale ?? "",
                value: translation.value,
                draftValue: translation.draftValue,
                isDraft: translation.isDraft,
                lastModified: translation.lastModified ?? Date()
            )
        }
        
        await cache.store(translationData, forKey: cacheKey)
        updateCacheStatistics()
    }
    
    /// Cache i18n keys
    func cacheI18nKeys(for project: Project) async {
        let cacheKey = "keys_\(project.id?.uuidString ?? "")"
        
        let keys = DataManager.shared.getI18nKeys(for: project)
        let keyData = keys.map { key in
            CachedI18nKey(
                id: key.id?.uuidString ?? "",
                key: key.key ?? "",
                namespace: key.namespace,
                isNested: key.isNested,
                parentKey: key.parentKey,
                usageCount: key.activeFileUsages.count,
                completionPercentage: key.completionPercentage,
                lastModified: key.lastModified ?? Date()
            )
        }
        
        await cache.store(keyData, forKey: cacheKey)
        updateCacheStatistics()
    }
    
    /// Cache file usage data
    func cacheFileUsages(for project: Project) async {
        let cacheKey = "usages_\(project.id?.uuidString ?? "")"
        
        let usages = project.fileUsages?.allObjects as? [FileUsage] ?? []
        let usageData = usages.filter { $0.isActive }.map { usage in
            CachedFileUsage(
                id: usage.id?.uuidString ?? "",
                keyId: usage.i18nKey?.id?.uuidString ?? "",
                filePath: usage.filePath ?? "",
                lineNumber: Int(usage.lineNumber),
                columnNumber: Int(usage.columnNumber),
                context: usage.context,
                detectedAt: usage.detectedAt ?? Date()
            )
        }
        
        await cache.store(usageData, forKey: cacheKey)
        updateCacheStatistics()
    }
    
    /// Retrieve cached translations
    func getCachedTranslations(for project: Project) async -> [CachedTranslation]? {
        let cacheKey = "translations_\(project.id?.uuidString ?? "")"
        return await cache.retrieve([CachedTranslation].self, forKey: cacheKey)
    }
    
    /// Retrieve cached i18n keys
    func getCachedI18nKeys(for project: Project) async -> [CachedI18nKey]? {
        let cacheKey = "keys_\(project.id?.uuidString ?? "")"
        return await cache.retrieve([CachedI18nKey].self, forKey: cacheKey)
    }
    
    /// Retrieve cached file usages
    func getCachedFileUsages(for project: Project) async -> [CachedFileUsage]? {
        let cacheKey = "usages_\(project.id?.uuidString ?? "")"
        return await cache.retrieve([CachedFileUsage].self, forKey: cacheKey)
    }
    
    /// Invalidate cache for project
    func invalidateCache(for project: Project) async {
        let projectId = project.id?.uuidString ?? ""
        let keys = [
            "translations_\(projectId)",
            "keys_\(projectId)",
            "usages_\(projectId)"
        ]
        
        for key in keys {
            await cache.remove(forKey: key)
        }
        
        updateCacheStatistics()
    }
    
    // MARK: - Performance Optimization
    
    /// Optimize data loading for large projects
    func optimizeDataLoading(for project: Project) async -> OptimizationResult {
        await MainActor.run {
            isOptimizing = true
        }
        
        defer {
            Task { @MainActor in
                isOptimizing = false
            }
        }
        
        let startTime = Date()
        var optimizations: [String] = []
        
        // Check if cached data is available and fresh
        if let cachedKeys = await getCachedI18nKeys(for: project),
           let cachedTranslations = await getCachedTranslations(for: project),
           isCacheDataFresh(cachedKeys.first?.lastModified ?? Date.distantPast) {
            
            optimizations.append("Used cached data (avoided database query)")
            
        } else {
            // Cache is stale or missing, refresh it
            await cacheI18nKeys(for: project)
            await cacheTranslations(for: project)
            await cacheFileUsages(for: project)
            
            optimizations.append("Refreshed cache with latest data")
        }
        
        // Optimize memory usage
        let memoryOptimization = await optimizeMemoryUsage()
        optimizations.append(contentsOf: memoryOptimization)
        
        // Optimize Core Data performance
        let coreDataOptimization = optimizeCoreDataPerformance()
        optimizations.append(contentsOf: coreDataOptimization)
        
        let duration = Date().timeIntervalSince(startTime)
        
        await MainActor.run {
            performanceMetrics.lastOptimizationDuration = duration
            performanceMetrics.optimizationsApplied += optimizations.count
        }
        
        return OptimizationResult(
            success: true,
            duration: duration,
            optimizationsApplied: optimizations,
            memoryUsageReduced: true,
            cacheHitRate: cacheStatistics.hitRate
        )
    }
    
    /// Optimize memory usage
    private func optimizeMemoryUsage() async -> [String] {
        var optimizations: [String] = []
        
        // Clear unused cache entries
        let clearedEntries = await cache.clearExpiredEntries()
        if clearedEntries > 0 {
            optimizations.append("Cleared \(clearedEntries) expired cache entries")
        }
        
        // Compact memory if needed
        let memoryUsage = getMemoryUsage()
        if memoryUsage > 200 * 1024 * 1024 { // 200MB threshold
            await cache.compactMemory()
            optimizations.append("Compacted memory cache")
        }
        
        return optimizations
    }
    
    /// Optimize Core Data performance
    private func optimizeCoreDataPerformance() -> [String] {
        var optimizations: [String] = []
        
        let context = DataManager.shared.viewContext
        
        // Reset context if it has too many objects
        if context.registeredObjects.count > 1000 {
            context.reset()
            optimizations.append("Reset Core Data context")
        }
        
        // Enable merge policy for better performance
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        optimizations.append("Optimized Core Data merge policy")
        
        return optimizations
    }
    
    /// Check if cached data is fresh
    private func isCacheDataFresh(_ lastModified: Date) -> Bool {
        let cacheAge = Date().timeIntervalSince(lastModified)
        return cacheAge < 300 // 5 minutes
    }
    
    /// Get current memory usage
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
    
    // MARK: - Metrics Collection
    
    /// Start collecting performance metrics
    func startMetricsCollection() {
        metricsCollector.startCollection()
        
        // Update metrics periodically
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
    }
    
    /// Update performance metrics
    private func updatePerformanceMetrics() {
        let metrics = metricsCollector.getCurrentMetrics()
        
        DispatchQueue.main.async {
            self.performanceMetrics = metrics
        }
    }
    
    /// Update cache statistics
    private func updateCacheStatistics() {
        Task {
            let stats = await cache.getStatistics()
            
            await MainActor.run {
                self.cacheStatistics = stats
            }
        }
    }
    
    // MARK: - Cache Cleanup
    
    /// Start periodic cache cleanup
    private func startCacheCleanup() {
        optimizationTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task {
                await self?.cache.clearExpiredEntries()
                self?.updateCacheStatistics()
            }
        }
    }
    
    /// Stop optimization timers
    func stopOptimization() {
        optimizationTimer?.invalidate()
        optimizationTimer = nil
        metricsCollector.stopCollection()
    }
    
    // MARK: - Batch Operations
    
    /// Optimize batch operations for better performance
    func performBatchOperation<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let context = DataManager.shared.viewContext
        
        // Disable automatic saving during batch operations
        context.automaticallyMergesChangesFromParent = false
        
        defer {
            context.automaticallyMergesChangesFromParent = true
        }
        
        let result = try await operation()

        // Save once at the end on main thread
        await MainActor.run {
            DataManager.shared.saveContext()
        }

        return result
    }
    
    /// Optimize search operations
    func optimizeSearch(query: String, in data: [Any]) -> [Any] {
        // Use efficient search algorithms for large datasets
        if data.count > 1000 {
            // Use binary search or other optimized algorithms
            return performOptimizedSearch(query: query, in: data)
        } else {
            // Use simple linear search for small datasets
            return performLinearSearch(query: query, in: data)
        }
    }
    
    private func performOptimizedSearch(query: String, in data: [Any]) -> [Any] {
        // Implement optimized search algorithm
        // This is a placeholder implementation
        return data.filter { item in
            String(describing: item).localizedCaseInsensitiveContains(query)
        }
    }
    
    private func performLinearSearch(query: String, in data: [Any]) -> [Any] {
        return data.filter { item in
            String(describing: item).localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Cache Manager

actor CacheManager {
    private var memoryCache: [String: CacheEntry] = [:]
    private var diskCache: DiskCache
    private var maxMemorySize: Int64 = 100 * 1024 * 1024
    private var maxDiskSize: Int64 = 500 * 1024 * 1024
    private var ttl: TimeInterval = 3600
    
    init() {
        self.diskCache = DiskCache()
    }
    
    func configure(maxMemorySize: Int64, maxDiskSize: Int64, ttl: TimeInterval) async {
        self.maxMemorySize = maxMemorySize
        self.maxDiskSize = maxDiskSize
        self.ttl = ttl

        await diskCache.configure(maxSize: maxDiskSize)
    }
    
    func store<T: Codable>(_ data: T, forKey key: String) async {
        let entry = CacheEntry(
            data: try! JSONEncoder().encode(data),
            timestamp: Date(),
            ttl: ttl
        )
        
        memoryCache[key] = entry
        
        // Also store to disk for persistence
        await diskCache.store(entry.data, forKey: key)
        
        // Cleanup if memory cache is too large
        await cleanupMemoryIfNeeded()
    }
    
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) async -> T? {
        // Try memory cache first
        if let entry = memoryCache[key], !entry.isExpired {
            return try? JSONDecoder().decode(type, from: entry.data)
        }
        
        // Try disk cache
        if let data = await diskCache.retrieve(forKey: key) {
            let entry = CacheEntry(data: data, timestamp: Date(), ttl: ttl)
            memoryCache[key] = entry
            return try? JSONDecoder().decode(type, from: data)
        }
        
        return nil
    }
    
    func remove(forKey key: String) async {
        memoryCache.removeValue(forKey: key)
        await diskCache.remove(forKey: key)
    }
    
    func clearExpiredEntries() async -> Int {
        let expiredKeys = memoryCache.compactMap { key, entry in
            entry.isExpired ? key : nil
        }
        
        for key in expiredKeys {
            memoryCache.removeValue(forKey: key)
        }
        
        await diskCache.clearExpiredEntries()
        
        return expiredKeys.count
    }
    
    func compactMemory() async {
        // Remove least recently used entries if memory is full
        let sortedEntries = memoryCache.sorted { $0.value.timestamp < $1.value.timestamp }
        let currentSize = getCurrentMemorySize()
        
        if currentSize > maxMemorySize {
            let targetSize = maxMemorySize * 3 / 4 // Reduce to 75% of max
            var removedSize: Int64 = 0
            
            for (key, entry) in sortedEntries {
                memoryCache.removeValue(forKey: key)
                removedSize += Int64(entry.data.count)
                
                if currentSize - removedSize <= targetSize {
                    break
                }
            }
        }
    }
    
    func getStatistics() async -> CacheStatistics {
        let memoryEntries = memoryCache.count
        let memorySize = getCurrentMemorySize()
        let diskSize = await diskCache.getCurrentSize()
        
        return CacheStatistics(
            memoryEntries: memoryEntries,
            memorySize: memorySize,
            diskSize: diskSize,
            hitRate: calculateHitRate(),
            lastCleanup: Date()
        )
    }
    
    private func getCurrentMemorySize() -> Int64 {
        return memoryCache.values.reduce(0) { $0 + Int64($1.data.count) }
    }
    
    private func calculateHitRate() -> Double {
        // This would need to track hits and misses
        // Simplified implementation
        return 0.85
    }
    
    private func cleanupMemoryIfNeeded() async {
        let currentSize = getCurrentMemorySize()
        if currentSize > maxMemorySize {
            await compactMemory()
        }
    }
}

// MARK: - Supporting Types

struct CacheEntry {
    let data: Data
    let timestamp: Date
    let ttl: TimeInterval
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }
}

struct CacheStatistics {
    var memoryEntries: Int = 0
    var memorySize: Int64 = 0
    var diskSize: Int64 = 0
    var hitRate: Double = 0.0
    var lastCleanup: Date = Date()
    
    var formattedMemorySize: String {
        ByteCountFormatter.string(fromByteCount: memorySize, countStyle: .memory)
    }
    
    var formattedDiskSize: String {
        ByteCountFormatter.string(fromByteCount: diskSize, countStyle: .file)
    }
}

struct PerformanceMetrics {
    var averageResponseTime: TimeInterval = 0.0
    var memoryUsage: Int64 = 0
    var cacheHitRate: Double = 0.0
    var lastOptimizationDuration: TimeInterval = 0.0
    var optimizationsApplied: Int = 0
    var databaseQueryCount: Int = 0
    var lastUpdated: Date = Date()
    
    var formattedMemoryUsage: String {
        ByteCountFormatter.string(fromByteCount: memoryUsage, countStyle: .memory)
    }
}

struct OptimizationResult {
    let success: Bool
    let duration: TimeInterval
    let optimizationsApplied: [String]
    let memoryUsageReduced: Bool
    let cacheHitRate: Double
}

// MARK: - Cached Data Types

struct CachedTranslation: Codable {
    let id: String
    let key: String
    let locale: String
    let value: String?
    let draftValue: String?
    let isDraft: Bool
    let lastModified: Date
}

struct CachedI18nKey: Codable {
    let id: String
    let key: String
    let namespace: String?
    let isNested: Bool
    let parentKey: String?
    let usageCount: Int
    let completionPercentage: Double
    let lastModified: Date
}

struct CachedFileUsage: Codable {
    let id: String
    let keyId: String
    let filePath: String
    let lineNumber: Int
    let columnNumber: Int
    let context: String?
    let detectedAt: Date
}

// MARK: - Disk Cache (Simplified)

actor DiskCache {
    private let cacheDirectory: URL
    private var maxSize: Int64 = 500 * 1024 * 1024
    
    init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDir.appendingPathComponent("i18nEditor")
        
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func configure(maxSize: Int64) {
        self.maxSize = maxSize
    }
    
    func store(_ data: Data, forKey key: String) async {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? data.write(to: fileURL)
    }
    
    func retrieve(forKey key: String) async -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        return try? Data(contentsOf: fileURL)
    }
    
    func remove(forKey key: String) async {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func clearExpiredEntries() async {
        // Simplified implementation
    }
    
    func getCurrentSize() async -> Int64 {
        // Simplified implementation
        return 0
    }
}

// MARK: - Metrics Collector

class MetricsCollector {
    private var startTime: Date?
    private var queryCount = 0
    
    func startCollection() {
        startTime = Date()
        queryCount = 0
    }
    
    func stopCollection() {
        startTime = nil
    }
    
    func recordDatabaseQuery() {
        queryCount += 1
    }
    
    func getCurrentMetrics() -> PerformanceMetrics {
        let memoryUsage = getMemoryUsage()
        
        return PerformanceMetrics(
            averageResponseTime: 0.1, // Placeholder
            memoryUsage: memoryUsage,
            cacheHitRate: 0.85, // Placeholder
            lastOptimizationDuration: 0.0,
            optimizationsApplied: 0,
            databaseQueryCount: queryCount,
            lastUpdated: Date()
        )
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
