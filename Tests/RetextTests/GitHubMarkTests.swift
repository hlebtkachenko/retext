import SwiftUI
import Testing
@testable import Retext

@Suite struct GitHubMarkTests {
    /// The parsed mark fills its 16 x 16 view box, with the arc drawn the short way round (bottom left).
    @Test func markFillsItsViewBox() {
        let path = GitHubMark.unitPath
        let box = path.boundingRect
        #expect(abs(box.minX) < 0.2 && abs(box.minY) < 0.2)
        #expect(abs(box.maxX - 16) < 0.2)
        #expect(box.maxY > 15.3 && box.maxY <= 16)  // the bottom is the gap between the two lower ends, at 15.45
        #expect(path.contains(CGPoint(x: 1.5, y: 10)))  // inside the arc's part of the circle
        #expect(path.contains(CGPoint(x: 8, y: 1)))     // top of the circle
        #expect(!path.contains(CGPoint(x: 8, y: 8)))    // the cat's head is cut out
    }
}
