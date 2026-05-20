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
        
        let destinationPath = (installPath as NSString).appendingPathComponent(driverName)
        
        // Prepare the script
        // 1. Create the HAL directory if it doesn't exist
        // 2. Copy the driver
        // 3. Restart coreaudiod using killall (launchctl kickstart is blocked by SIP on modern macOS)
        let script = """
        do shell script "mkdir -p '\(installPath)' && cp -R '\(bundledDriverPath)' '\(installPath)/' && killall coreaudiod" with administrator privileges
        """
        
        return await withCheckedContinuation { continuation in
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            
            logger.info("Executing driver installation script...")
            
            _ = appleScript?.executeAndReturnError(&error)
            
            if let error = error {
                let errorCode = error[NSAppleScript.errorNumber] as? Int
                if errorCode == -128 { // User cancelled
                    logger.info("Driver installation cancelled by user")
                    continuation.resume(returning: .cancelled)
                } else {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    logger.error("Driver installation failed: \(errorMessage) (code: \(errorCode ?? 0))")
                    continuation.resume(returning: .failure(errorMessage))
                }
            } else {
                logger.info("Driver installation successful")
                continuation.resume(returning: .success)
            }
        }
    }
    
    func uninstall() async -> InstallationResult {
        let script = """
        do shell script "rm -rf '\(installPath)/\(driverName)' && killall coreaudiod" with administrator privileges
        """
        
        return await withCheckedContinuation { continuation in
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            
            _ = appleScript?.executeAndReturnError(&error)
            
            if let error = error {
                let errorCode = error[NSAppleScript.errorNumber] as? Int
                if errorCode == -128 {
                    continuation.resume(returning: .cancelled)
                } else {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(returning: .failure(errorMessage))
                }
            } else {
                continuation.resume(returning: .success)
            }
        }
    }
}
