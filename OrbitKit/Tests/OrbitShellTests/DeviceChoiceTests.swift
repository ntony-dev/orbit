import OrbitCore
import OrbitEngine
@testable import OrbitShell
import Testing

struct DeviceChoiceTests {
    private let speaker = PlaybackDevice(id: "new-id", name: "Kitchen", kind: .speaker)
    private let laptop = PlaybackDevice(id: "mac", name: "MacBook", kind: .computer)

    @Test func listsDevicesWhenNothingIsSaved() {
        let choices = DeviceChoice.choices(devices: [laptop], preferred: nil, status: .notSet)
        #expect(choices == [DeviceChoice(reference: DeviceReference(id: "mac", name: "MacBook"), title: "MacBook")])
    }

    @Test func savedDeviceUnderANewIDKeepsTheSavedTagSoItStaysSelected() {
        let saved = DeviceReference(id: "old-id", name: "Kitchen")
        let choices = DeviceChoice.choices(devices: [laptop, speaker], preferred: saved, status: .available(speaker))
        #expect(choices.map(\.reference) == [DeviceReference(id: "mac", name: "MacBook"), saved])
        #expect(choices.map(\.title) == ["MacBook", "Kitchen"])
    }

    @Test func missingDeviceIsMarkedUnavailable() {
        let saved = DeviceReference(id: "gone", name: "Bedroom")
        let choices = DeviceChoice.choices(devices: [laptop], preferred: saved, status: .missing(saved))
        #expect(choices.last == DeviceChoice(reference: saved, title: "Bedroom (unavailable)"))
    }

    @Test func unloadedListShowsTheSavedDeviceWithoutCallingItUnavailable() {
        let saved = DeviceReference(id: "phone", name: "iPhone")
        let choices = DeviceChoice.choices(devices: [], preferred: saved, status: .unverified(saved))
        #expect(choices == [DeviceChoice(reference: saved, title: "iPhone")])
    }
}
