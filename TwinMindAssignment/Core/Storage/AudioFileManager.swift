import Foundation
import CryptoKit
import SwiftData

/// Secure audio file management with encryption at rest and storage optimization
@MainActor
class AudioFileManager: ObservableObject {
    
    // MARK: - Properties
    
    /// Storage configuration options
    struct StorageConfiguration {
        let maxStorageSize: Int64 // bytes
        let autoCleanupEnabled: Bool
        let encryptionEnabled: Bool
        let compressionLevel: CompressionLevel
        let retentionPeriod: TimeInterval // seconds
        
        static let `default` = StorageConfiguration(
            maxStorageSize: 5 * 1024 * 1024 * 1024, // 5GB
            autoCleanupEnabled: true,
            encryptionEnabled: true,
            compressionLevel: .balanced,
            retentionPeriod: 90 * 24 * 3600 // 90 days
        )
    }
    
    enum CompressionLevel: CaseIterable {
        case none, low, balanced, high
        
        var compressionQuality: Float {
            switch self {
            case .none: return 1.0
            case .low: return 0.9
            case .balanced: return 0.7
            case .high: return 0.5
            }
        }
    }
    

    
    @Published var configuration: StorageConfiguration
    @Published var currentStorageUsage: Int64 = 0
    @Published var availableStorage: Int64 = 0
    @Published var isCleanupInProgress = false
    
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let encryptedDirectory: URL
    private let tempDirectory: URL
    private var modelContext: ModelContext?
    
    // Encryption key derived from device keychain
    private var encryptionKey: SymmetricKey {
        let keyData = getOrCreateEncryptionKey()
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - Initialization
    
    init(configuration: StorageConfiguration = .default) {
        self.configuration = configuration
        
        // Create directory structure
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.baseDirectory = documentsPath.appendingPathComponent("AudioRecordings")
        self.encryptedDirectory = baseDirectory.appendingPathComponent("Encrypted")
        self.tempDirectory = baseDirectory.appendingPathComponent("Temp")
        
        createDirectoryStructure()
        // Initialize storage info synchronously
        currentStorageUsage = getCurrentStorageUsage()
        availableStorage = getAvailableStorage()
    }
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - File Operations
    
    /// Save audio file with optional encryption
    func saveAudioFile(from sourceURL: URL, for session: Session) async throws -> URL {
        // Check available storage
        try await checkStorageCapacity(requiredSize: getFileSize(at: sourceURL))
        
        // Generate secure filename
        let filename = generateSecureFilename(for: session)
        let destinationURL: URL
        
        if configuration.encryptionEnabled {
            destinationURL = encryptedDirectory.appendingPathComponent(filename)
            try await encryptAndSaveFile(from: sourceURL, to: destinationURL)
        } else {
            destinationURL = baseDirectory.appendingPathComponent(filename)
            try await copyFile(from: sourceURL, to: destinationURL)
        }
        
        // Update storage tracking
        await updateStorageInfo()
        
        return destinationURL
    }
    
    /// Load audio file with automatic decryption
    func loadAudioFile(from encryptedURL: URL) async throws -> URL {
        if configuration.encryptionEnabled && encryptedURL.path.contains("Encrypted") {
            return try await decryptFile(from: encryptedURL)
        } else {
            // File is not encrypted, return as-is
            return encryptedURL
        }
    }
    
    /// Delete audio file and cleanup
    func deleteAudioFile(at url: URL) async throws {
        try fileManager.removeItem(at: url)
        
        // Also remove temporary decrypted version if exists
        let tempURL = tempDirectory.appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: tempURL.path) {
            try? fileManager.removeItem(at: tempURL)
        }
        
        await updateStorageInfo()
    }
    
    // MARK: - Storage Management
    
    /// Check if sufficient storage is available
    private func checkStorageCapacity(requiredSize: Int64) async throws {
        let available = getAvailableStorage()
        let currentUsage = getCurrentStorageUsage()
        
        if available < requiredSize {
            throw NSError(domain: "AudioFileManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient storage space available"])
        }
        
        if currentUsage + requiredSize > configuration.maxStorageSize {
            // Try cleanup first
            await performAutomaticCleanup()
            
            let newUsage = getCurrentStorageUsage()
            if newUsage + requiredSize > configuration.maxStorageSize {
                throw NSError(domain: "AudioFileManagerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Insufficient storage space available"])
            }
        }
    }
    
    /// Update storage usage information
    func updateStorageInfo() async {
        currentStorageUsage = getCurrentStorageUsage()
        availableStorage = getAvailableStorage()
    }
    
    /// Get current storage usage
    private func getCurrentStorageUsage() -> Int64 {
        let urls = [baseDirectory, encryptedDirectory, tempDirectory]
        var totalSize: Int64 = 0
        
        for url in urls {
            totalSize += getDirectorySize(at: url)
        }
        
        return totalSize
    }
    
    /// Get available storage on device
    private func getAvailableStorage() -> Int64 {
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: baseDirectory.path),
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return 0
        }
        return freeSize
    }
    
    // MARK: - Cleanup Operations
    
    /// Perform automatic cleanup based on configuration
    func performAutomaticCleanup() async {
        guard !isCleanupInProgress else { return }
        isCleanupInProgress = true
        
        defer {
            Task { @MainActor in
                self.isCleanupInProgress = false
            }
        }
        
        // Remove old temporary files
        await cleanupTemporaryFiles()
        
        // Remove old recordings based on retention policy
        if configuration.autoCleanupEnabled {
            await cleanupOldRecordings()
        }
        
        // Update storage info
        await updateStorageInfo()
    }
    
    /// Remove temporary decrypted files
    private func cleanupTemporaryFiles() async {
        guard let tempContents = try? fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        
        let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour old
        
        for url in tempContents {
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < cutoffDate {
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    /// Remove old recordings based on retention period
    private func cleanupOldRecordings() async {
        guard let modelContext = modelContext else { return }
        
        let cutoffDate = Date().addingTimeInterval(-configuration.retentionPeriod)
        
        // Fetch old sessions from SwiftData
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { session in
                session.startTime < cutoffDate
            }
        )
        
        guard let oldSessions = try? modelContext.fetch(descriptor) else { return }
        
        for session in oldSessions {
            // Delete associated files
            if let audioURL = session.fileURL {
                try? await deleteAudioFile(at: audioURL)
            }
            
            // Remove segments files
            for segment in session.segments {
                if let segmentURL = segment.fileURL {
                    try? await deleteAudioFile(at: segmentURL)
                }
            }
            
            // Delete from database
            modelContext.delete(session)
        }
        
        try? modelContext.save()
    }
    
    /// Force cleanup to free specific amount of space
    func forceCleanup(targetFreeSpace: Int64) async throws {
        isCleanupInProgress = true
        
        defer {
            Task { @MainActor in
                self.isCleanupInProgress = false
            }
        }
        
        await performAutomaticCleanup()
        
        // If still not enough space, remove oldest recordings
        while getCurrentStorageUsage() > (configuration.maxStorageSize - targetFreeSpace) {
            guard await removeOldestRecording() else {
                break // No more recordings to remove
            }
        }
        
        await updateStorageInfo()
    }
    
    /// Remove the oldest recording session
    private func removeOldestRecording() async -> Bool {
        guard let modelContext = modelContext else { return false }
        
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        guard let sessions = try? modelContext.fetch(descriptor),
              let oldestSession = sessions.first else {
            return false
        }
        
        // Delete files
        if let audioURL = oldestSession.fileURL {
            try? await deleteAudioFile(at: audioURL)
        }
        
        for segment in oldestSession.segments {
            if let segmentURL = segment.fileURL {
                try? await deleteAudioFile(at: segmentURL)
            }
        }
        
        // Delete from database
        modelContext.delete(oldestSession)
        try? modelContext.save()
        
        return true
    }
    
    // MARK: - Encryption Operations
    
    /// Encrypt and save file
    private func encryptAndSaveFile(from sourceURL: URL, to destinationURL: URL) async throws {
        let data = try Data(contentsOf: sourceURL)
        let encryptedData = try encryptData(data)
        try encryptedData.write(to: destinationURL)
    }
    
    /// Decrypt file to temporary location
    private func decryptFile(from encryptedURL: URL) async throws -> URL {
        let encryptedData = try Data(contentsOf: encryptedURL)
        let decryptedData = try decryptData(encryptedData)
        
        let tempURL = tempDirectory.appendingPathComponent(encryptedURL.lastPathComponent)
        try decryptedData.write(to: tempURL)
        
        return tempURL
    }
    
    /// Encrypt data using AES-GCM
    private func encryptData(_ data: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
            return sealedBox.combined!
        } catch {
            throw NSError(domain: "AudioFileManagerError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encrypt audio file"])
        }
    }
    
    /// Decrypt data using AES-GCM
    private func decryptData(_ encryptedData: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: encryptionKey)
        } catch {
            throw NSError(domain: "AudioFileManagerError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to decrypt audio file"])
        }
    }
    
    // MARK: - Security
    
    /// Get or create encryption key from keychain
    private func getOrCreateEncryptionKey() -> Data {
        let keyTag = "com.twinmind.audiorecorder.encryptionkey"
        
        // Try to get existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let keyData = result as? Data {
            return keyData
        }
        
        // Create new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        
        // Store in keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(addQuery as CFDictionary, nil)
        return keyData
    }
    
    // MARK: - Utilities
    
    /// Create directory structure
    private func createDirectoryStructure() {
        let directories = [baseDirectory, encryptedDirectory, tempDirectory]
        
        for directory in directories {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
    
    /// Generate secure filename for session
    private func generateSecureFilename(for session: Session) -> String {
        let timestamp = Int(session.startTime.timeIntervalSince1970)
        let randomComponent = UUID().uuidString.prefix(8)
        return "recording_\(timestamp)_\(randomComponent).m4a"
    }
    
    /// Get file size at URL
    private func getFileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }
    
    /// Get directory size recursively
    private func getDirectorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        
        return totalSize
    }
    
    /// Copy file from source to destination
    private func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
    
    // MARK: - Configuration Updates
    
    /// Update storage configuration
    func updateConfiguration(_ newConfiguration: StorageConfiguration) async {
        self.configuration = newConfiguration
        
        // Trigger cleanup if needed
        if newConfiguration.autoCleanupEnabled {
            await performAutomaticCleanup()
        }
    }
    
    /// Get storage usage summary
    func getStorageUsageSummary() -> (current: Int64, maximum: Int64, percentage: Double) {
        let current = currentStorageUsage
        let maximum = configuration.maxStorageSize
        let percentage = maximum > 0 ? Double(current) / Double(maximum) : 0.0
        
        return (current, maximum, percentage)
    }
} 
