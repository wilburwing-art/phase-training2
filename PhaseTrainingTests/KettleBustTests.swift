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

    /// The snowboard tip is the lowest ink of any pose: the board rect spans
    /// y 174...185 and tilts -12 ± 5 degrees on top of the figure's ±5 degree
    /// rock, which drops its left end to about y 205. Flex's window ends at
    /// 188 and would cut it flat.
    func testSnowboardCropClearsTheBoardTip() {
        let crop = KettleBust.crop(for: .snowboard)
        XCTAssertGreaterThan(crop.origin.y + crop.side, 204.5, "crop cuts the board tip")
        XCTAssertLessThan(crop.origin.y, 36, "crop clips the handle")
        XCTAssertLessThan(crop.origin.x, 21, "crop clips the board's left end")
        XCTAssertGreaterThan(crop.origin.x + crop.side, 147, "crop clips the trailing fist")
    }

    /// Bike wheels are r16 + stroke at y 176, and the -4 degree lean drops the
    /// back wheel to about y 197.
    func testBikeCropClearsTheWheels() {
        let crop = KettleBust.crop(for: .bike)
        XCTAssertGreaterThan(crop.origin.y + crop.side, 197.4, "crop cuts the wheels")
        XCTAssertLessThan(crop.origin.x, 2, "crop clips the speed lines")
        XCTAssertGreaterThan(crop.origin.x + crop.side, 147, "crop clips the front wheel")
    }

    /// Flex keeps its tuned window so the pinned extremes above still apply.
    func testFlexUsesTheDefaultCrop() {
        let crop = KettleBust.crop(for: .flex)
        XCTAssertEqual(crop.origin, KettleBust.cropOrigin)
        XCTAssertEqual(crop.side, KettleBust.cropSide)
    }

    /// The pressed still for flex stays the squeeze.
    func testPressedFrameForFlexIsThePeak() {
        XCTAssertEqual(KettleBust.pressedFrame(for: .flex), KettleBust.peakFlex, accuracy: 1e-9)
    }

    /// MASCOT2.md sets a 64pt floor on live surfaces; the old disc was 52.
    func testDefaultSizeMeetsTheLiveSurfaceFloor() {
        XCTAssertGreaterThanOrEqual(KettleBust().size, 64)
    }
}
