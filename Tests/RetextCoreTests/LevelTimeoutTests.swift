import Testing
@testable import RetextCore

@Suite struct LevelTimeoutTests {
    @Test func maxGetsTheLongerTimeout() {
        #expect(Level.allCases.map(\.timeout) == [.seconds(60), .seconds(60), .seconds(120)])
    }
}
