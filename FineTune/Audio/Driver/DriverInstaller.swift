// FineTune/Audio/Driver/DriverInstaller.swift
import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "DriverInstaller")

@MainActor
final class DriverInstaller {
    static let shared = DriverInstaller()
    
    private let driverName = "FineTuneDriver.driver"
    private let installPath = "/Library/Audio/Plug-Ins/HAL"
    
    var isDriverInstalled: Bool {
        let fullPath = (installPath as NSString).appendingPathComponent(driverName)
        return FileManager.default.fileExists(atPath: fullPath)
    }
    
    var needsUpdate: Bool {
        guard isDriverInstalled else { return false }
        
        guard let bundledDriverPath = Bundle.main.path(forResource: "FineTuneDriver", ofType: "driver") else { return false }
        let installedDriverPath = (installPath as NSString).appendingPathComponent(driverName)
        
        // Compare the main executable files
        let bundledExecutablePath = (bundledDriverPath as NSString).appendingPathComponent("Contents/MacOS/FineTuneDriver")
        let installedExecutablePath = (installedDriverPath as NSString).appendingPathComponent("Contents/MacOS/FineTuneDriver")
        
        guard FileManager.default.fileExists(atPath: installedExecutablePath) else {
            // Driver bundle exists but executable is missing - definitely needs update/reinstall
            return true
        }
        
        // Binary comparison of the executables
        let exeIdentical = FileManager.default.contentsEqual(atPath: bundledExecutablePath, andPath: installedExecutablePath)
        
        // Also check Info.plist for any configuration changes
        let bundledPlistPath = (bundledDriverPath as NSString).appendingPathComponent("Contents/Info.plist")
        let installedPlistPath = (installedDriverPath as NSString).appendingPathComponent("Contents/Info.plist")
        let plistIdentical = FileManager.default.contentsEqual(atPath: bundledPlistPath, andPath: installedPlistPath)
        
        let isIdentical = exeIdentical && plistIdentical
        
        if !isIdentical {
            logger.info("Driver update needed: bundled files differ from installed version (Exe: \(exeIdentical), Plist: \(plistIdentical))")
        }
        
        return !isIdentical
    }
    
    enum InstallationResult {
        case success
        case failure(String)
        case cancelled
    }
    
    func install() async -> InstallationResult {
        guard let bundledDriverPath = Bundle.main.path(forResource: "FineTuneDriver", ofType: "driver") else {
            logger.error("Could not find bundled driver")
            return .failure("Bundled driver not found in the application package.")
        }
        
        let command = installationShellCommand(sourcePath: bundledDriverPath)
        return await runPrivilegedShellCommand(command, operation: "driver installation")
    }
    
    func uninstall() async -> InstallationResult {
        let command = """
        set -e
        rm -rf \(Self.shellQuoted((installPath as NSString).appendingPathComponent(driverName)))
        killall -TERM coreaudiod 2>/dev/null || true
        """
        return await runPrivilegedShellCommand(command, operation: "driver uninstall")
    }

    private func installationShellCommand(sourcePath: String) -> String {
        let installPath = Self.shellQuoted(installPath)
        let sourcePath = Self.shellQuoted(sourcePath)
        let finalPath = Self.shellQuoted((self.installPath as NSString).appendingPathComponent(driverName))
        let tempPath = Self.shellQuoted((self.installPath as NSString).appendingPathComponent(".\(driverName).installing"))

        return """
        set -e
        mkdir -p \(installPath)
        rm -rf \(tempPath)
        ditto \(sourcePath) \(tempPath)
        xattr -dr com.apple.quarantine \(tempPath) 2>/dev/null || true
        chown -R root:wheel \(tempPath)
        chmod -R go-w \(tempPath)
        rm -rf \(finalPath)
        mv \(tempPath) \(finalPath)
        killall -TERM coreaudiod 2>/dev/null || true
        """
    }

    private nonisolated func runPrivilegedShellCommand(_ command: String, operation: String) async -> InstallationResult {
        await Task.detached(priority: .userInitiated) {
            let escapedCommand = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = #"do shell script "\#(escapedCommand)" with administrator privileges"#
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            
            logger.info("Executing \(operation, privacy: .public) script...")
            
            _ = appleScript?.executeAndReturnError(&error)
            
            if let error = error {
                let errorCode = error[NSAppleScript.errorNumber] as? Int
                if errorCode == -128 { // User cancelled
                    logger.info("\(operation, privacy: .public) cancelled by user")
                    return .cancelled
                } else {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    logger.error("\(operation, privacy: .public) failed: \(errorMessage) (code: \(errorCode ?? 0))")
                    return .failure(errorMessage)
                }
            } else {
                logger.info("\(operation, privacy: .public) successful")
                return .success
            }
        }.value
    }

    private nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
