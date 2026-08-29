//
//  KettleBustTests.swift
//  PhaseTrainingTests
//
//  The crop is a window onto KettleView's 160x200 design space, and it is
//  wrong in a way nothing renders as an error: too tight and the shoes are
//  cut flat at the frame edge, which the old disc hid and a container-less
//  control does not. These pin the window against the pose extremes.
//

import XCTest
import CoreGraphics
@testable import PhaseTraining

final class KettleBustTests: XCTestCase {

    private var cropMinX: CGFloat { KettleBust.cropOrigin.x }
    private var cropMinY: CGFloat { KettleBust.cropOrigin.y }
    private var cropMaxX: CGFloat { KettleBust.cropOrigin.x + KettleBust.cropSide }
    private var cropMaxY: CGFloat { KettleBust.cropOrigin.y + KettleBust.cropSide }

    /// The flex loop lifts the whole figure 2.5 units at peak, so the top of
    /// the handle is the highest ink in the design and must stay inside.
    func testCropClearsTheHandleAtPeakFlex() {
        let handleTop: CGFloat = 42 - 6   // arc apex minus half the 12pt stroke
        XCTAssertLessThan(cropMinY, handleTop - 2.5,
                          "crop top clips the handle when the flex lift is applied")
    }

    /// The shoes are the lowest ink. Cutting them is the failure the wider
    /// crop exists to prevent.
    func testCropClearsTheShoes() {
        let shoeBottom: CGFloat = 176 + 10
        XCTAssertGreaterThan(cropMaxY, shoeBottom,
                             "crop bottom cuts the shoes off flat")
    }

    /// Widest ink at peak flex is the elbow bump: centre 26, radius 8 + 6.
    func testCropClearsTheElbowsAtPeakFlex() {
        let elbowLeft: CGFloat = 26 - 14
        let elbowRight: CGFloat = 134 + 14
        XCTAssertLessThan(cropMinX, elbowLeft, "crop clips the left elbow")
        XCTAssertGreaterThan(cropMaxX, elbowRight, "crop clips the right elbow")
    }

    /// Square, so the control is square and the mascot is not stretched.
    func testCropIsSquare() {
        XCTAssertEqual(cropMaxX - cropMinX, cropMaxY - cropMinY)
    }

    /// flex = 0.5 - 0.5*cos(2*pi*t/P) reaches 1 at t = P/2. If this drifts the
    /// pressed state stops looking like a squeeze and nothing reports it.
    func testPeakFlexIsHalfThePeriod() {
        XCTAssertEqual(KettleBust.peakFlex, KettlePose.flex.period / 2, accuracy: 1e-9)
        let value = 0.5 - 0.5 * cos(2 * Double.pi * KettleBust.peakFlex / KettlePose.flex.period)
        XCTAssertEqual(value, 1.0, accuracy: 1e-9)
    }

    /// MASCOT2.md sets a 64pt floor on live surfaces; the old disc was 52.
    func testDefaultSizeMeetsTheLiveSurfaceFloor() {
        XCTAssertGreaterThanOrEqual(KettleBust().size, 64)
    }
}
