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

    @Test("Special macOS outputs are not exposed in FineTune device lists")
    func specialOutputsAreHiddenFromFineTuneDeviceLists() {
        let monitor = MockAudioDeviceMonitor()
        let speakers = AudioDevice(id: 101, uid: "speakers", name: "MacBook Pro Speakers", icon: nil, supportsAutoEQ: false)
        let airPods = AudioDevice(id: 102, uid: "airpods", name: "Sam's AirPods Pro", icon: nil, supportsAutoEQ: true)
        let virtual = AudioDevice(id: 103, uid: "FineTune.VirtualOutput", name: "FineTune Output", icon: nil, supportsAutoEQ: false)
        monitor.addOutputDevice(speakers)
        monitor.addOutputDevice(airPods)
        monitor.addOutputDevice(virtual)

        let settings = SettingsManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        settings.setDevicePriorityOrder([airPods.uid, speakers.uid])

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

        #expect(engine.outputDevices.map(\.uid) == ["speakers"])
        #expect(engine.prioritySortedOutputDevices.map(\.uid) == ["speakers"])
    }

    @Test("Bluetooth input devices are not exposed in FineTune device lists")
    func bluetoothInputsAreHiddenFromFineTuneDeviceLists() {
        let monitor = MockAudioDeviceMonitor()
        let builtInMic = AudioDevice(id: 101, uid: "built-in-mic", name: "MacBook Pro Microphone", icon: nil, supportsAutoEQ: false)
        let airPodsMic = AudioDevice(id: 102, uid: "airpods-mic", name: "Sam's AirPods Pro", icon: nil, supportsAutoEQ: false)
        monitor.inputDevices = [builtInMic, airPodsMic]

        let settings = SettingsManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        settings.setInputDevicePriorityOrder([airPodsMic.uid, builtInMic.uid])

        let volume = MockDeviceVolumeProviding(deviceMonitor: monitor)
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

        #expect(engine.inputDevices.map(\.uid) == ["built-in-mic"])
        #expect(engine.prioritySortedInputDevices.map(\.uid) == ["built-in-mic"])
    }
}
