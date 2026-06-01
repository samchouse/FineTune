import AppKit
import AudioToolbox
import Foundation
import Testing
@testable import FineTune

@Suite("Audio device ordering")
@MainActor
struct AudioDeviceOrderingTests {
    @Test("Selecting playback output preserves Core Audio device order")
    func playbackSelectionPreservesCoreAudioOrder() {
        let monitor = MockAudioDeviceMonitor()
        let speakers = AudioDevice(id: 101, uid: "speakers", name: "MacBook Pro Speakers", icon: nil, supportsAutoEQ: false)
        let display = AudioDevice(id: 102, uid: "display", name: "Studio Display", icon: nil, supportsAutoEQ: false)
        let virtual = AudioDevice(id: 103, uid: "FineTune.VirtualOutput", name: "FineTune Output", icon: nil, supportsAutoEQ: false)
        monitor.addOutputDevice(speakers)
        monitor.addOutputDevice(display)
        monitor.addOutputDevice(virtual)

        let settings = SettingsManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        settings.setDevicePriorityOrder([speakers.uid, display.uid])

        let volume = MockDeviceVolumeProviding(deviceMonitor: monitor)
        volume.defaultDeviceID = virtual.id
        volume.defaultDeviceUID = virtual.uid

        let engine = AudioEngine(
            permission: AudioRecordingPermission(),
            settingsManager: settings,
            autoEQProfileManager: AutoEQProfileManager(),
            deviceProvider: monitor,
            processMonitor: AudioProcessMonitor(),
            deviceVolumeMonitor: volume,
            isAlive: { _ in true },
            startMonitorsAutomatically: false
        )

        #expect(engine.prioritySortedOutputDevices.map(\.uid) == ["speakers", "display"])
        #expect(engine.outputDevices.map(\.uid) == ["speakers", "display"])

        _ = engine.setPlaybackOutputDevice(display.id)

        #expect(engine.outputDevices.map(\.uid) == ["speakers", "display"])
    }
}
