import AudioToolbox
import AppKit
import Foundation
import Testing
@testable import FineTune

@Suite("FineTune virtual output playback sync")
@MainActor
struct VirtualOutputPlaybackSyncTests {
    @Test("Changing FineTune's current physical playback volume also updates the virtual HAL output")
    func physicalPlaybackVolumeWritesVirtualOutput() {
        let harness = makeHarness()

        harness.engine.setPlaybackOutputVolume(for: harness.physical.id, to: 0.42)

        #expect(harness.volume.volumes[harness.physical.id] == 0.42)
        #expect(harness.volume.volumes[harness.virtual.id] == 0.42)
        #expect(harness.volume.setVolumeCalls.contains { $0.deviceID == harness.virtual.id && $0.volume == 0.42 })
    }

    @Test("Changing FineTune's current physical playback mute also updates the virtual HAL output")
    func physicalPlaybackMuteWritesVirtualOutput() {
        let harness = makeHarness()

        harness.engine.setPlaybackOutputMute(for: harness.physical.id, to: true)

        #expect(harness.volume.muteStates[harness.physical.id] == true)
        #expect(harness.volume.muteStates[harness.virtual.id] == true)
        #expect(harness.volume.setMuteCalls.contains { $0.deviceID == harness.virtual.id && $0.muted })
    }

    @Test("Changing the virtual HAL output mirrors to the physical playback output")
    func virtualOutputWritesPhysicalPlaybackOutput() {
        let harness = makeHarness()

        harness.engine.setPlaybackOutputVolume(for: harness.virtual.id, to: 0.37)
        harness.engine.setPlaybackOutputMute(for: harness.virtual.id, to: true)

        #expect(harness.volume.volumes[harness.virtual.id] == 0.37)
        #expect(harness.volume.volumes[harness.physical.id] == 0.37)
        #expect(harness.volume.muteStates[harness.virtual.id] == true)
        #expect(harness.volume.muteStates[harness.physical.id] == true)
    }

    @Test("Following system default resolves FineTune Output to the selected physical playback output")
    func followDefaultRoutesToPhysicalPlaybackOutput() {
        let harness = makeHarness()
        let app = AudioApp(
            id: 1234,
            processObjectIDs: [],
            name: "Safari",
            icon: NSImage(),
            bundleID: "com.apple.Safari"
        )

        harness.engine.setDevice(for: app, deviceUID: nil)

        #expect(harness.engine.getDeviceUID(for: app) == harness.physical.uid)
        #expect(harness.engine.isFollowingDefault(for: app))
    }

    @Test("Switching playback devices restores each device's saved volume")
    func playbackDeviceSwitchRestoresPerDeviceVolume() {
        let harness = makeHarness()
        let second = AudioDevice(id: 303, uid: "second-output", name: "Display", icon: nil, supportsAutoEQ: false)
        harness.deviceMonitor.addOutputDevice(second)

        harness.engine.setPlaybackOutputVolume(for: harness.physical.id, to: 0.5)
        _ = harness.engine.setPlaybackOutputDevice(second.id)
        harness.engine.setPlaybackOutputVolume(for: second.id, to: 0.8)
        _ = harness.engine.setPlaybackOutputDevice(harness.physical.id)

        #expect(harness.volume.volumes[harness.physical.id] == 0.5)
        #expect(harness.volume.volumes[harness.virtual.id] == 0.5)
        #expect(harness.volume.volumes[second.id] == 0.8)
    }

    @Test("Restart restores last FineTune playback output without changing macOS default")
    func restartRestoresLastInternalPlaybackOutputOnly() {
        let settings = SettingsManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        settings.setDevicePriorityOrder(["speakers", "display"])
        settings.setLastPlaybackOutputDeviceUID("display")

        let deviceMonitor = MockAudioDeviceMonitor()
        let speakers = AudioDevice(id: 101, uid: "speakers", name: "Speakers", icon: nil, supportsAutoEQ: false)
        let display = AudioDevice(id: 202, uid: "display", name: "Display", icon: nil, supportsAutoEQ: false)
        let virtual = AudioDevice(id: 303, uid: "FineTune.VirtualOutput", name: "FineTune Output", icon: nil, supportsAutoEQ: false)
        deviceMonitor.addOutputDevice(speakers)
        deviceMonitor.addOutputDevice(display)
        deviceMonitor.addOutputDevice(virtual)

        let volume = MockDeviceVolumeProviding(deviceMonitor: deviceMonitor)
        volume.defaultDeviceID = virtual.id
        volume.defaultDeviceUID = virtual.uid

        let engine = AudioEngine(
            settingsManager: settings,
            deviceProvider: deviceMonitor,
            processMonitor: AudioProcessMonitor(),
            deviceVolumeMonitor: volume,
            isAlive: { _ in true },
            startMonitorsAutomatically: false
        )

        #expect(engine.isCurrentPlaybackOutput(display))
        #expect(volume.defaultDeviceID == virtual.id)
        #expect(volume.defaultDeviceUID == virtual.uid)
    }

    private struct Harness {
        let engine: AudioEngine
        let volume: MockDeviceVolumeProviding
        let deviceMonitor: MockAudioDeviceMonitor
        let physical: AudioDevice
        let virtual: AudioDevice
    }

    private func makeHarness() -> Harness {
        let deviceMonitor = MockAudioDeviceMonitor()
        let physical = AudioDevice(id: 101, uid: "physical-output", name: "Speakers", icon: nil, supportsAutoEQ: false)
        let virtual = AudioDevice(id: 202, uid: "FineTune.VirtualOutput", name: "FineTune Output", icon: nil, supportsAutoEQ: false)
        deviceMonitor.addOutputDevice(physical)
        deviceMonitor.addOutputDevice(virtual)

        let volume = MockDeviceVolumeProviding(deviceMonitor: deviceMonitor)
        volume.defaultDeviceID = virtual.id
        volume.defaultDeviceUID = virtual.uid
        volume.volumes[physical.id] = 1.0
        volume.volumes[virtual.id] = 1.0
        volume.muteStates[physical.id] = false
        volume.muteStates[virtual.id] = false

        let settings = SettingsManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        settings.setDevicePriorityOrder([physical.uid])

        let engine = AudioEngine(
            settingsManager: settings,
            deviceProvider: deviceMonitor,
            processMonitor: AudioProcessMonitor(),
            deviceVolumeMonitor: volume,
            isAlive: { _ in true },
            startMonitorsAutomatically: false
        )

        return Harness(engine: engine, volume: volume, deviceMonitor: deviceMonitor, physical: physical, virtual: virtual)
    }
}
