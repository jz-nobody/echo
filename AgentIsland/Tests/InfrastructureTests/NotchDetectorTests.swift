import Testing
@testable import AgentIsland

@Suite("NotchDetector Tests")
struct NotchDetectorTests {

    @Test("detect returns valid NotchInfo with positive dimensions")
    func detectReturnsValidInfo() {
        let info = NotchDetector.detect()

        #expect(info.notchHeight > 0)
        #expect(info.screenFrame.width > 0)
        #expect(info.screenFrame.height > 0)
        #expect(info.barOriginX > 0)
        #expect(info.barOriginY > 0)
    }

    @Test("barOriginX is within screen bounds")
    func barOriginXWithinScreen() {
        let info = NotchDetector.detect()

        #expect(info.barOriginX >= info.screenFrame.minX)
        #expect(info.barOriginX < info.screenFrame.maxX)
    }

    @Test("barOriginY is at the top of the screen")
    func barOriginYAtTop() {
        let info = NotchDetector.detect()

        let distanceFromTop = info.screenFrame.maxY - info.barOriginY
        #expect(distanceFromTop <= 40)
    }

    @Test("notchHeight is reasonable (24-44pt range)")
    func notchHeightReasonable() {
        let info = NotchDetector.detect()

        #expect(info.notchHeight >= 24)
        #expect(info.notchHeight <= 44)
    }
}
