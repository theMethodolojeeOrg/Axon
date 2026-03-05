//
//  MacSystemService.swift
//  Axon
//
//  Native macOS system operations service.
//  On iOS, operations throw errors indicating bridge connection is required.
//

@preconcurrency import Foundation
import os.log

#if os(macOS)
import AppKit
import IOKit
import SystemConfiguration
import UserNotifications
import UniformTypeIdentifiers

@MainActor
final class MacSystemService {
    static let shared = MacSystemService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "MacSystemService")

    // MARK: - Blocked Commands (Security)

    private let blockedPatterns: [String] = [
        "rm -rf /",
        "rm -rf ~",
        "rm -rf /*",
        "sudo ",
        "chmod 777",
        "chmod -R 777",
        "mkfs",
        "fdisk",
        "dd if=",
        "> /dev/",
        ":(){ :|:& };:",  // Fork bomb
        "mv /* ",
        "wget.*\\|.*sh",
        "curl.*\\|.*sh",
        "eval ",
        "exec ",
    ]

    private init() {
        logger.info("MacSystemService initialized")
    }

    // MARK: - System Info

    func getSystemInfo() async throws -> SystemInfoResult {
        logger.debug("Getting system info")

        let processInfo = ProcessInfo.processInfo
        let hostName = processInfo.hostName
        let osVersion = processInfo.operatingSystemVersionString

        // Get OS build number
        var size: Int = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var osBuild = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &osBuild, &size, nil, 0)
        let osBuildString = String(cString: osBuild)

        // Get CPU info
        let cpuModel = getCPUModel()
        let cpuCores = processInfo.processorCount
        let cpuCoresLogical = processInfo.activeProcessorCount

        // Get memory info
        let memoryTotal = Double(processInfo.physicalMemory) / (1024 * 1024 * 1024)
        let (memoryUsed, memoryFree) = getMemoryUsage()
        let memoryUsagePercent = (memoryUsed / memoryTotal) * 100

        // Get uptime
        let uptimeSeconds = Int(processInfo.systemUptime)
        let uptimeFormatted = formatUptime(seconds: uptimeSeconds)

        // Boot time
        var bootTime = timeval()
        var size2 = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &bootTime, &size2, nil, 0)
        let bootDate = Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))

        return SystemInfoResult(
            hostname: hostName,
            osVersion: osVersion,
            osBuild: osBuildString,
            cpuModel: cpuModel,
            cpuCores: cpuCores,
            cpuCoresLogical: cpuCoresLogical,
            memoryTotalGB: round(memoryTotal * 100) / 100,
            memoryUsedGB: round(memoryUsed * 100) / 100,
            memoryFreeGB: round(memoryFree * 100) / 100,
            memoryUsagePercent: round(memoryUsagePercent * 10) / 10,
            uptimeSeconds: uptimeSeconds,
            uptimeFormatted: uptimeFormatted,
            bootTime: bootDate
        )
    }

    private func getCPUModel() -> String {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpuModel = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &cpuModel, &size, nil, 0)
        return String(cString: cpuModel)
    }

    private func getMemoryUsage() -> (used: Double, free: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0)
        }

        let pageSize = Double(vm_kernel_page_size)
        let freeMemory = Double(stats.free_count) * pageSize / (1024 * 1024 * 1024)
        let activeMemory = Double(stats.active_count) * pageSize / (1024 * 1024 * 1024)
        let inactiveMemory = Double(stats.inactive_count) * pageSize / (1024 * 1024 * 1024)
        let wiredMemory = Double(stats.wire_count) * pageSize / (1024 * 1024 * 1024)
        let compressedMemory = Double(stats.compressor_page_count) * pageSize / (1024 * 1024 * 1024)

        let usedMemory = activeMemory + wiredMemory + compressedMemory
        return (usedMemory, freeMemory + inactiveMemory)
    }

    private func formatUptime(seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Running Processes

    func getRunningProcesses(limit: Int = 20) async throws -> ProcessListResult {
        logger.debug("Getting running processes (limit: \(limit))")

        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        var processes: [MacProcessInfo] = []

        for app in runningApps.prefix(limit) {
            let process = MacProcessInfo(
                pid: Int(app.processIdentifier),
                name: app.localizedName ?? "Unknown",
                cpuPercent: 0,  // Would need additional API for accurate CPU %
                memoryPercent: 0,
                memoryMB: 0,
                status: app.isTerminated ? "terminated" : (app.isActive ? "active" : "running"),
                user: nil
            )
            processes.append(process)
        }

        return ProcessListResult(
            processes: processes,
            totalCount: runningApps.count
        )
    }

    // MARK: - Disk Usage

    func getDiskUsage(path: String = "/") async throws -> DiskUsageResult {
        logger.debug("Getting disk usage for: \(path)")

        let fileManager = FileManager.default
        let expandedPath = NSString(string: path).expandingTildeInPath

        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: expandedPath)

            let totalSize = (attrs[.systemSize] as? Int64) ?? 0
            let freeSize = (attrs[.systemFreeSize] as? Int64) ?? 0
            let usedSize = totalSize - freeSize

            let totalGB = Double(totalSize) / (1024 * 1024 * 1024)
            let usedGB = Double(usedSize) / (1024 * 1024 * 1024)
            let freeGB = Double(freeSize) / (1024 * 1024 * 1024)
            let usagePercent = (Double(usedSize) / Double(totalSize)) * 100

            return DiskUsageResult(
                path: path,
                totalGB: round(totalGB * 100) / 100,
                usedGB: round(usedGB * 100) / 100,
                freeGB: round(freeGB * 100) / 100,
                usagePercent: round(usagePercent * 10) / 10,
                fileSystem: nil
            )
        } catch {
            throw MacSystemError.operationFailed("Failed to get disk usage: \(error.localizedDescription)")
        }
    }

    // MARK: - Clipboard

    func getClipboardContent() async throws -> ClipboardReadResult {
        logger.debug("Reading clipboard")

        let pasteboard = NSPasteboard.general

        if let string = pasteboard.string(forType: .string) {
            return ClipboardReadResult(
                content: string,
                hasContent: true,
                contentType: "text"
            )
        } else if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil {
            return ClipboardReadResult(
                content: nil,
                hasContent: true,
                contentType: "image"
            )
        } else if pasteboard.propertyList(forType: .fileURL) != nil {
            return ClipboardReadResult(
                content: nil,
                hasContent: true,
                contentType: "file"
            )
        } else {
            return ClipboardReadResult(
                content: nil,
                hasContent: false,
                contentType: "unknown"
            )
        }
    }

    func setClipboardContent(_ content: String) async throws -> ClipboardWriteResult {
        logger.debug("Setting clipboard content")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(content, forType: .string)

        return ClipboardWriteResult(success: success)
    }

    // MARK: - Notifications

    func sendNotification(title: String, message: String, subtitle: String? = nil, soundName: String? = nil) async throws -> NotificationSendResult {
        logger.debug("Sending notification: \(title)")

        // Use UNUserNotificationCenter for modern macOS
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        if let soundName = soundName {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }

        let id = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        do {
            try await UNUserNotificationCenter.current().add(request)
            return NotificationSendResult(success: true, notificationId: id)
        } catch {
            logger.error("Failed to send notification: \(error.localizedDescription)")
            return NotificationSendResult(success: false, notificationId: nil)
        }
    }

    // MARK: - Spotlight Search

    func spotlightSearch(query: String, limit: Int = 20, contentType: String? = nil) async throws -> SpotlightSearchResult {
        logger.debug("Spotlight search: \(query)")

        return try await withCheckedThrowingContinuation { continuation in
            let metadataQuery = NSMetadataQuery()

            var predicateFormat = "kMDItemDisplayName contains[cd] %@"
            if let contentType = contentType {
                predicateFormat += " && kMDItemContentType == %@"
                metadataQuery.predicate = NSPredicate(format: predicateFormat, query, contentType)
            } else {
                metadataQuery.predicate = NSPredicate(format: predicateFormat, query)
            }

            metadataQuery.searchScopes = [NSMetadataQueryLocalComputerScope]

            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery,
                queue: .main
            ) { _ in
                metadataQuery.stop()

                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }

                var items: [SpotlightItem] = []
                let count = min(metadataQuery.resultCount, limit)

                for i in 0..<count {
                    guard let item = metadataQuery.result(at: i) as? NSMetadataItem else { continue }

                    let path = item.value(forAttribute: NSMetadataItemPathKey) as? String ?? ""
                    let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? ""
                    let displayName = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                    let contentType = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
                    let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int
                    let modifiedDate = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
                    let createdDate = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date

                    items.append(SpotlightItem(
                        path: path,
                        name: name,
                        displayName: displayName,
                        contentType: contentType,
                        sizeBytes: size,
                        modifiedDate: modifiedDate,
                        createdDate: createdDate
                    ))
                }

                continuation.resume(returning: SpotlightSearchResult(
                    results: items,
                    totalFound: metadataQuery.resultCount,
                    searchTime: 0
                ))
            }

            DispatchQueue.main.async {
                metadataQuery.start()
            }

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if metadataQuery.isGathering {
                    metadataQuery.stop()
                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    continuation.resume(throwing: MacSystemError.timeout)
                }
            }
        }
    }

    // MARK: - File Find

    func findFiles(pattern: String, directory: String = "~", maxDepth: Int = 3) async throws -> FileFindResult {
        logger.info("Finding files: pattern='\(pattern)' in directory='\(directory)' maxDepth=\(maxDepth)")

        let fileManager = FileManager.default
        let expandedPath = NSString(string: directory).expandingTildeInPath

        logger.info("Expanded path: \(expandedPath)")

        // Check if directory exists
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            logger.error("Directory does not exist or is not a directory: \(expandedPath)")
            throw MacSystemError.operationFailed("Directory does not exist: \(expandedPath)")
        }

        var foundFiles: [FoundFile] = []
        var filesEnumerated = 0

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: expandedPath),
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Cannot create enumerator for: \(expandedPath)")
            throw MacSystemError.operationFailed("Cannot enumerate directory: \(directory)")
        }

        for case let fileURL as URL in enumerator {
            filesEnumerated += 1

            // Check depth
            let components = fileURL.pathComponents
            let baseComponents = URL(fileURLWithPath: expandedPath).pathComponents
            let currentDepth = components.count - baseComponents.count

            if currentDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let fileName = fileURL.lastPathComponent

            // Simple pattern matching (supports * wildcard)
            let matches = matchesPattern(fileName, pattern: pattern)

            if matches {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let size = resourceValues?.fileSize

                foundFiles.append(FoundFile(
                    path: fileURL.path,
                    name: fileName,
                    sizeBytes: size,
                    isDirectory: isDirectory
                ))

                if foundFiles.count >= 100 {
                    logger.info("Reached 100 file limit")
                    break
                }
            }
        }

        logger.info("File find complete: enumerated=\(filesEnumerated), matched=\(foundFiles.count)")

        return FileFindResult(
            files: foundFiles,
            searchDirectory: expandedPath,
            totalFound: foundFiles.count
        )
    }

    private func matchesPattern(_ name: String, pattern: String) -> Bool {
        if pattern.contains("*") {
            let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*") + "$"
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                let range = NSRange(name.startIndex..., in: name)
                return regex.firstMatch(in: name, options: [], range: range) != nil
            }
        }
        return name.localizedCaseInsensitiveContains(pattern)
    }

    // MARK: - File List

    func listFiles(path: String = ".", includeHidden: Bool = false, maxItems: Int = 100) async throws -> MacFileListResult {
        logger.info("Listing files: path='\(path)' includeHidden=\(includeHidden) maxItems=\(maxItems)")

        let fileManager = FileManager.default
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        // Check if directory exists
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir) else {
            logger.error("Path does not exist: \(expandedPath)")
            throw MacSystemError.operationFailed("Path does not exist: \(expandedPath)")
        }

        guard isDir.boolValue else {
            logger.error("Path is not a directory: \(expandedPath)")
            throw MacSystemError.operationFailed("Path is not a directory: \(expandedPath)")
        }

        var items: [MacFileListItem] = []

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: includeHidden ? [] : [.skipsHiddenFiles]
            )

            for fileURL in contents.prefix(maxItems) {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let size = resourceValues?.fileSize
                let modified = resourceValues?.contentModificationDate

                items.append(MacFileListItem(
                    name: fileURL.lastPathComponent,
                    path: fileURL.path,
                    isDirectory: isDirectory,
                    sizeBytes: size,
                    modifiedDate: modified
                ))
            }

            // Sort: directories first, then by name
            items.sort { item1, item2 in
                if item1.isDirectory != item2.isDirectory {
                    return item1.isDirectory
                }
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }

            logger.info("Listed \(items.count) items in \(expandedPath)")

            return MacFileListResult(
                path: expandedPath,
                items: items,
                totalCount: contents.count,
                truncated: contents.count > maxItems
            )
        } catch {
            logger.error("Failed to list directory: \(error.localizedDescription)")
            throw MacSystemError.operationFailed("Failed to list directory: \(error.localizedDescription)")
        }
    }

    // MARK: - File Read

    func readFile(path: String, maxBytes: Int? = nil, encoding: String = "utf8") async throws -> MacFileReadResult {
        logger.info("Reading file: \(path)")

        let fileManager = FileManager.default
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        // Check if file exists
        guard fileManager.fileExists(atPath: expandedPath) else {
            return MacFileReadResult(
                path: expandedPath,
                name: url.lastPathComponent,
                exists: false,
                content: nil,
                sizeBytes: nil,
                truncated: false,
                encoding: encoding,
                errorMessage: "File does not exist"
            )
        }

        // Check if it's a directory
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir)
        if isDir.boolValue {
            return MacFileReadResult(
                path: expandedPath,
                name: url.lastPathComponent,
                exists: true,
                content: nil,
                sizeBytes: nil,
                truncated: false,
                encoding: encoding,
                errorMessage: "Path is a directory, not a file"
            )
        }

        do {
            // Get file size
            let attrs = try fileManager.attributesOfItem(atPath: expandedPath)
            let fileSize = attrs[.size] as? Int ?? 0

            // Default max bytes to 1MB to prevent memory issues
            let effectiveMaxBytes = maxBytes ?? 1_000_000
            let shouldTruncate = fileSize > effectiveMaxBytes

            // Read file content
            let data: Data
            if shouldTruncate {
                // Read only up to maxBytes
                let fileHandle = try FileHandle(forReadingFrom: url)
                data = fileHandle.readData(ofLength: effectiveMaxBytes)
                try fileHandle.close()
            } else {
                data = try Data(contentsOf: url)
            }

            // Decode based on encoding
            let content: String?
            switch encoding.lowercased() {
            case "utf8", "utf-8":
                content = String(data: data, encoding: .utf8)
            case "utf16", "utf-16":
                content = String(data: data, encoding: .utf16)
            case "ascii":
                content = String(data: data, encoding: .ascii)
            case "latin1", "iso-8859-1":
                content = String(data: data, encoding: .isoLatin1)
            default:
                content = String(data: data, encoding: .utf8)
            }

            if content == nil {
                // Binary file or encoding issue
                return MacFileReadResult(
                    path: expandedPath,
                    name: url.lastPathComponent,
                    exists: true,
                    content: nil,
                    sizeBytes: fileSize,
                    truncated: shouldTruncate,
                    encoding: encoding,
                    errorMessage: "Could not decode file as \(encoding) - may be binary"
                )
            }

            logger.info("File read complete: \(fileSize) bytes, truncated: \(shouldTruncate)")

            return MacFileReadResult(
                path: expandedPath,
                name: url.lastPathComponent,
                exists: true,
                content: content,
                sizeBytes: fileSize,
                truncated: shouldTruncate,
                encoding: encoding,
                errorMessage: nil
            )
        } catch {
            logger.error("Failed to read file: \(error.localizedDescription)")
            return MacFileReadResult(
                path: expandedPath,
                name: url.lastPathComponent,
                exists: true,
                content: nil,
                sizeBytes: nil,
                truncated: false,
                encoding: encoding,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - File Metadata

    func getFileMetadata(path: String) async throws -> FileMetadataResult {
        logger.debug("Getting file metadata: \(path)")

        let fileManager = FileManager.default
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        let exists = fileManager.fileExists(atPath: expandedPath)

        guard exists else {
            return FileMetadataResult(
                path: expandedPath,
                name: url.lastPathComponent,
                exists: false,
                isDirectory: false,
                isSymlink: false,
                sizeBytes: nil,
                permissions: nil,
                owner: nil,
                group: nil,
                createdDate: nil,
                modifiedDate: nil,
                accessedDate: nil,
                contentType: nil
            )
        }

        do {
            let attrs = try fileManager.attributesOfItem(atPath: expandedPath)
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentTypeKey])

            let isDirectory = resourceValues.isDirectory ?? false
            let isSymlink = resourceValues.isSymbolicLink ?? false
            let size = attrs[.size] as? Int
            let permissions = String(format: "%o", (attrs[.posixPermissions] as? Int) ?? 0)
            let owner = attrs[.ownerAccountName] as? String
            let group = attrs[.groupOwnerAccountName] as? String
            let createdDate = attrs[.creationDate] as? Date
            let modifiedDate = attrs[.modificationDate] as? Date
            let contentType = resourceValues.contentType?.identifier

            return FileMetadataResult(
                path: expandedPath,
                name: url.lastPathComponent,
                exists: true,
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                sizeBytes: size,
                permissions: permissions,
                owner: owner,
                group: group,
                createdDate: createdDate,
                modifiedDate: modifiedDate,
                accessedDate: nil,
                contentType: contentType
            )
        } catch {
            throw MacSystemError.operationFailed("Failed to get file metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Running Applications

    func getRunningApplications() async throws -> AppListResult {
        logger.debug("Getting running applications")

        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        var apps: [RunningApp] = []

        for app in runningApps {
            guard let name = app.localizedName, !name.isEmpty else { continue }

            apps.append(RunningApp(
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                pid: Int(app.processIdentifier),
                isActive: app.isActive,
                isHidden: app.isHidden,
                icon: nil  // Could encode icon to base64 if needed
            ))
        }

        return AppListResult(applications: apps)
    }

    // MARK: - Launch Application

    func launchApplication(name: String, arguments: [String]? = nil) async throws -> AppLaunchResult {
        logger.info("Launching application: \(name)")

        let workspace = NSWorkspace.shared

        // Try to find the app by name
        let appURL: URL?

        if name.hasSuffix(".app") {
            appURL = URL(fileURLWithPath: "/Applications/\(name)")
        } else {
            appURL = workspace.urlForApplication(withBundleIdentifier: name) ??
                     URL(fileURLWithPath: "/Applications/\(name).app")
        }

        guard let url = appURL, FileManager.default.fileExists(atPath: url.path) else {
            return AppLaunchResult(
                success: false,
                pid: nil,
                bundleIdentifier: nil,
                errorMessage: "Application not found: \(name)"
            )
        }

        do {
            let config = NSWorkspace.OpenConfiguration()
            if let arguments = arguments {
                config.arguments = arguments
            }

            let app = try await workspace.openApplication(at: url, configuration: config)

            return AppLaunchResult(
                success: true,
                pid: Int(app.processIdentifier),
                bundleIdentifier: app.bundleIdentifier,
                errorMessage: nil
            )
        } catch {
            return AppLaunchResult(
                success: false,
                pid: nil,
                bundleIdentifier: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - Screenshot

    func takeScreenshot(path: String? = nil, display: Int? = nil, includeWindows: Bool = true) async throws -> ScreenshotResult {
        logger.info("Taking screenshot")

        // Use screencapture command for reliability
        let tempPath = path ?? NSTemporaryDirectory() + "axon_screenshot_\(UUID().uuidString).png"

        var args = ["-x"]  // No sound
        if !includeWindows {
            args.append("-C")  // Capture cursor
        }
        args.append(tempPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = try Data(contentsOf: URL(fileURLWithPath: tempPath))

                // Get image dimensions
                if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                   let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
                    let width = properties[kCGImagePropertyPixelWidth as String] as? Int
                    let height = properties[kCGImagePropertyPixelHeight as String] as? Int

                    if path == nil {
                        // Return base64 data and clean up temp file
                        let base64 = data.base64EncodedString()
                        try? FileManager.default.removeItem(atPath: tempPath)

                        return ScreenshotResult(
                            success: true,
                            path: nil,
                            imageData: base64,
                            width: width,
                            height: height,
                            errorMessage: nil
                        )
                    } else {
                        return ScreenshotResult(
                            success: true,
                            path: tempPath,
                            imageData: nil,
                            width: width,
                            height: height,
                            errorMessage: nil
                        )
                    }
                }
            }

            return ScreenshotResult(
                success: false,
                path: nil,
                imageData: nil,
                width: nil,
                height: nil,
                errorMessage: "Screenshot capture failed"
            )
        } catch {
            return ScreenshotResult(
                success: false,
                path: nil,
                imageData: nil,
                width: nil,
                height: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - Network Info

    func getNetworkInfo() async throws -> NetworkInfoResult {
        logger.debug("Getting network info")

        var interfaces: [NetworkInterface] = []

        // Get network interfaces
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            throw MacSystemError.operationFailed("Failed to get network interfaces")
        }
        defer { freeifaddrs(ifaddr) }

        var seen = Set<String>()

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)

            guard !seen.contains(name) else { continue }
            seen.insert(name)

            let family = ptr.pointee.ifa_addr.pointee.sa_family
            var ipv4: String?
            var ipv6: String?

            if family == UInt8(AF_INET) {
                var addr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var sockaddr = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                inet_ntop(AF_INET, &sockaddr.sin_addr, &addr, socklen_t(INET_ADDRSTRLEN))
                ipv4 = String(cString: addr)
            } else if family == UInt8(AF_INET6) {
                var addr = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                var sockaddr = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                inet_ntop(AF_INET6, &sockaddr.sin6_addr, &addr, socklen_t(INET6_ADDRSTRLEN))
                ipv6 = String(cString: addr)
            }

            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            interfaces.append(NetworkInterface(
                name: name,
                displayName: name,
                ipv4Address: ipv4,
                ipv6Address: ipv6,
                macAddress: nil,
                isUp: isUp,
                isLoopback: isLoopback,
                mtu: nil,
                speed: nil
            ))
        }

        // Get WiFi info using airport command
        var wifiSSID: String?
        let airportProcess = Process()
        airportProcess.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport")
        airportProcess.arguments = ["-I"]

        let pipe = Pipe()
        airportProcess.standardOutput = pipe

        try? airportProcess.run()
        airportProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            for line in output.components(separatedBy: "\n") {
                if line.contains("SSID:") && !line.contains("BSSID") {
                    wifiSSID = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        return NetworkInfoResult(
            interfaces: interfaces,
            wifiSSID: wifiSSID,
            wifiBSSID: nil,
            externalIP: nil
        )
    }

    // MARK: - Ping

    func pingHost(host: String, count: Int = 4, timeout: Int = 5000) async throws -> PingResult {
        logger.info("Pinging host: \(host)")

        // Validate host to prevent command injection
        let validHostPattern = "^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$"
        guard let regex = try? NSRegularExpression(pattern: validHostPattern),
              regex.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil else {
            throw MacSystemError.operationFailed("Invalid host format")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", String(count), "-t", String(timeout / 1000), host]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse ping output
            var packetsTransmitted = 0
            var packetsReceived = 0
            var minTime: Double?
            var avgTime: Double?
            var maxTime: Double?

            for line in output.components(separatedBy: "\n") {
                if line.contains("packets transmitted") {
                    let parts = line.components(separatedBy: ",")
                    if let transmitted = parts.first?.components(separatedBy: " ").first {
                        packetsTransmitted = Int(transmitted) ?? 0
                    }
                    if parts.count > 1, let received = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first {
                        packetsReceived = Int(received) ?? 0
                    }
                }
                if line.contains("min/avg/max") {
                    if let timePart = line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) {
                        let times = timePart.components(separatedBy: "/")
                        if times.count >= 3 {
                            minTime = Double(times[0])
                            avgTime = Double(times[1])
                            maxTime = Double(times[2].components(separatedBy: " ").first ?? "")
                        }
                    }
                }
            }

            let packetLoss = packetsTransmitted > 0 ?
                Double(packetsTransmitted - packetsReceived) / Double(packetsTransmitted) * 100 : 100

            return PingResult(
                success: packetsReceived > 0,
                host: host,
                packetsTransmitted: packetsTransmitted,
                packetsReceived: packetsReceived,
                packetLoss: packetLoss,
                minTime: minTime,
                avgTime: avgTime,
                maxTime: maxTime,
                errorMessage: packetsReceived == 0 ? "No response from host" : nil
            )
        } catch {
            return PingResult(
                success: false,
                host: host,
                packetsTransmitted: 0,
                packetsReceived: 0,
                packetLoss: 100,
                minTime: nil,
                avgTime: nil,
                maxTime: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - Shell Execute

    func executeShellCommand(command: String, timeout: Int = 30000, workingDirectory: String? = nil) async throws -> ShellExecuteResult {
        logger.info("Executing shell command")

        // Security check - block dangerous commands
        for pattern in blockedPatterns {
            if command.lowercased().contains(pattern.lowercased()) {
                logger.warning("Blocked dangerous command pattern: \(pattern)")
                return ShellExecuteResult(
                    success: false,
                    stdout: "",
                    stderr: "",
                    exitCode: -1,
                    timedOut: false,
                    executionTime: 0,
                    blocked: true,
                    blockedReason: "Command contains blocked pattern: \(pattern)"
                )
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        if let workingDir = workingDirectory {
            let expandedPath = NSString(string: workingDir).expandingTildeInPath
            process.currentDirectoryURL = URL(fileURLWithPath: expandedPath)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()

        do {
            try process.run()

            // Set up timeout
            let timeoutSeconds = Double(timeout) / 1000.0
            var timedOut = false

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }

            process.waitUntilExit()

            let executionTime = Date().timeIntervalSince(startTime)

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return ShellExecuteResult(
                success: process.terminationStatus == 0 && !timedOut,
                stdout: stdout,
                stderr: stderr,
                exitCode: Int(process.terminationStatus),
                timedOut: timedOut,
                executionTime: executionTime,
                blocked: false,
                blockedReason: nil
            )
        } catch {
            return ShellExecuteResult(
                success: false,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: -1,
                timedOut: false,
                executionTime: 0,
                blocked: false,
                blockedReason: nil
            )
        }
    }
}

#else
// MARK: - iOS Stub Implementation

@MainActor
final class MacSystemService {
    static let shared = MacSystemService()

    private init() {}

    func getSystemInfo() async throws -> SystemInfoResult {
        throw MacSystemError.requiresBridge("System info")
    }

    func getRunningProcesses(limit: Int = 20) async throws -> ProcessListResult {
        throw MacSystemError.requiresBridge("Process list")
    }

    func getDiskUsage(path: String = "/") async throws -> DiskUsageResult {
        throw MacSystemError.requiresBridge("Disk usage")
    }

    func getClipboardContent() async throws -> ClipboardReadResult {
        throw MacSystemError.requiresBridge("Clipboard read")
    }

    func setClipboardContent(_ content: String) async throws -> ClipboardWriteResult {
        throw MacSystemError.requiresBridge("Clipboard write")
    }

    func sendNotification(title: String, message: String, subtitle: String? = nil, soundName: String? = nil) async throws -> NotificationSendResult {
        throw MacSystemError.requiresBridge("Notification")
    }

    func spotlightSearch(query: String, limit: Int = 20, contentType: String? = nil) async throws -> SpotlightSearchResult {
        throw MacSystemError.requiresBridge("Spotlight search")
    }

    func findFiles(pattern: String, directory: String = "~", maxDepth: Int = 3) async throws -> FileFindResult {
        throw MacSystemError.requiresBridge("File find")
    }

    func listFiles(path: String = ".", includeHidden: Bool = false, maxItems: Int = 100) async throws -> MacFileListResult {
        throw MacSystemError.requiresBridge("File list")
    }

    func readFile(path: String, maxBytes: Int? = nil, encoding: String = "utf8") async throws -> MacFileReadResult {
        throw MacSystemError.requiresBridge("File read")
    }

    func getFileMetadata(path: String) async throws -> FileMetadataResult {
        throw MacSystemError.requiresBridge("File metadata")
    }

    func getRunningApplications() async throws -> AppListResult {
        throw MacSystemError.requiresBridge("Application list")
    }

    func launchApplication(name: String, arguments: [String]? = nil) async throws -> AppLaunchResult {
        throw MacSystemError.requiresBridge("Application launch")
    }

    func takeScreenshot(path: String? = nil, display: Int? = nil, includeWindows: Bool = true) async throws -> ScreenshotResult {
        throw MacSystemError.requiresBridge("Screenshot")
    }

    func getNetworkInfo() async throws -> NetworkInfoResult {
        throw MacSystemError.requiresBridge("Network info")
    }

    func pingHost(host: String, count: Int = 4, timeout: Int = 5000) async throws -> PingResult {
        throw MacSystemError.requiresBridge("Ping")
    }

    func executeShellCommand(command: String, timeout: Int = 30000, workingDirectory: String? = nil) async throws -> ShellExecuteResult {
        throw MacSystemError.requiresBridge("Shell execute")
    }
}

#endif
