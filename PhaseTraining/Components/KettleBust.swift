//
//  KettleBust.swift
//  PhaseTraining
//
//  Kettle framed for a small control: the mascot cropped to a square and
//  drawn with no container, so the kettlebell's own round silhouette is the
//  shape rather than a disc drawn around it.
//
//  The crop is a window onto KettleView's 160×200 design space. It is NOT the
//  bell alone — the lime handle is the kettlebell signature, and a crop that
//  cuts it leaves a round cream face that could be anything.
//
//  Why 156 and not a tighter box: the flex loop lifts the whole figure 2.5
//  units at peak and the shoes reach y=186, so anything shorter cuts the
//  shoes off flat at the frame edge. With a disc that cut hid behind the
//  circle; with no container it reads as a crop mark. See MASCOT2.md.
//

import SwiftUI

struct KettleBust: View {

    var pose: KettlePose = .flex
    /// Off by default so a still frame stays a one-argument call. The live
    /// caller (CoachBubble) turns it on: the corner Kettle runs the same flex
    /// loop as the big one on Today, and the overlay is already scoped to
    /// consent + pro + not-on-profile + no-active-session, so the running
    /// TimelineView is not paid for on every tab.
    var animated: Bool = false
    /// Loop time to hold when not animating. 0 is the rest frame.
    var frozenAt: TimeInterval = 0
    /// Rendered edge length. MASCOT2.md sets a 64pt floor on live surfaces.
    var size: CGFloat = 64

    /// Design-space window. Holds the whole figure at every loop value.
    static let cropOrigin = CGPoint(x: 2, y: 32)
    static let cropSide: CGFloat = 156

    /// Peak of the flex squeeze: flex = 0.5 - 0.5·cos(2π·t/P) reaches 1 at P/2.
    static let peakFlex: TimeInterval = KettlePose.flex.period / 2

    var body: some View {
        let unit = size / Self.cropSide
        KettleView(pose: pose, animated: animated, frozenAt: frozenAt)
            .frame(width: 160 * unit, height: 200 * unit)
            .offset(x: -Self.cropOrigin.x * unit, y: -Self.cropOrigin.y * unit)
            .frame(width: size, height: size, alignment: .topLeading)
            .clipped()
    }
}

#Preview {
    HStack(spacing: 24) {
        KettleBust()
        KettleBust(frozenAt: KettleBust.peakFlex)
        KettleBust(animated: true)
    }
    .padding(40)
    .background(Color.bg)
}
