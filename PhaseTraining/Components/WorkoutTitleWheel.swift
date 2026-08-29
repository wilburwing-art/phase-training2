//
//  WorkoutTitleWheel.swift
//  PhaseTraining
//
//  Today's title, made scrollable. Swiping it left/right switches which
//  workout today runs, with a selection haptic on each change.
//
//  Why the title and not a new control: Today is meant to answer one question
//  and adding a picker tile would be a second thing to read. Turning the copy
//  that is already the largest element on the screen into the control adds a
//  capability without adding a surface.
//
//  Deliberately BOUNDED. An unbounded library browser on Today would make the
//  page a picker, which is what it was just stripped of. The wheel carries the
//  planned session plus a few saved workouts; "See all" opens the existing
//  OverrideTodaySheet, which is also the accessible path (see below).
//
//  Accessibility: a horizontally scrolling title is a poor VoiceOver target
//  and does not survive large Dynamic Type well, so the wheel exposes an
//  .adjustable action (swipe up/down to move between workouts) and the whole
//  header keeps a tap that opens the full sheet.
//

import SwiftUI
import UIKit

/// One stop on the wheel.
struct WorkoutWheelOption: Identifiable, Equatable {
    /// `nil` routineId means the planned session — the generator's own choice.
    let id: String
    let title: String
    let subtitle: String?
    /// nil for the planned session; a CustomRoutine.id for a saved workout.
    let routineId: String?

    static let plannedId = "__planned__"
}

struct WorkoutTitleWheel: View {
    let options: [WorkoutWheelOption]
    /// Read-only. The wheel does not own which workout is selected — that is
    /// derived from PlanStore's overrides — so it reports a change through
    /// `onCommit` and re-reads this on the next render.
    let selectedId: String
    /// Fired when the user settles on a different workout.
    let onCommit: (WorkoutWheelOption) -> Void
    /// Opens the full picker. Also the accessible path to everything the
    /// wheel's cap leaves out.
    let onSeeAll: () -> Void

    @State private var scrolledId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let haptics = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(options) { option in
                            Text(option.title)
                                .styled(.displayL)
                                .foregroundStyle(option.id == selectedId ? Color.ink : Color.ink3)
                                .lineSpacing(-2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: geo.size.width, alignment: .leading)
                                .id(option.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledId)
                .scrollDisabled(options.count <= 1)
            }
            .frame(height: titleHeight)
            if options.count > 1 { pips }
        }
        .onAppear { scrolledId = selectedId }
        // Selection can also change from elsewhere (the See-all sheet writes
        // the same override), so follow it rather than fighting it.
        .onChange(of: selectedId) { _, new in
            if scrolledId != new { scrolledId = new }
        }
        .onChange(of: scrolledId) { _, new in
            guard let new, new != selectedId,
                  let option = options.first(where: { $0.id == new }) else { return }
            // Prepare-then-fire is what makes the pulse land with the snap
            // rather than a frame late.
            Self.haptics.prepare()
            Self.haptics.selectionChanged()
            onCommit(option)
        }
        // One element for VoiceOver, driven by swipe up/down rather than by
        // the horizontal scroll, which VoiceOver consumes for navigation.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("today-workout-wheel")
        .accessibilityLabel("Today's workout")
        .accessibilityValue(options.first(where: { $0.id == selectedId })?.title ?? "")
        .accessibilityHint("Swipe up or down to switch workouts. Double tap to see all.")
        .accessibilityAdjustableAction { direction in
            guard let i = options.firstIndex(where: { $0.id == selectedId }) else { return }
            let next: Int
            switch direction {
            case .increment: next = min(i + 1, options.count - 1)
            case .decrement: next = max(i - 1, 0)
            @unknown default: return
            }
            guard next != i else { return }
            // Moving scrolledId is enough: the onChange above commits and
            // fires the haptic, so the two paths cannot diverge.
            scrolledId = options[next].id
        }
        .accessibilityAction { onSeeAll() }
    }

    /// Two lines of displayL plus the leading it carries. Fixed so the header
    /// does not jump as titles of different lengths scroll past.
    private var titleHeight: CGFloat { 84 }

    /// Position, not a control. Tapping a pip would be a second hit target
    /// competing with the scroll for the same pixels.
    private var pips: some View {
        HStack(spacing: 5) {
            ForEach(options) { option in
                Capsule()
                    .fill(option.id == selectedId ? Color.accent : Color.line)
                    .frame(width: option.id == selectedId ? 14 : 5, height: 3)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                               value: selectedId)
            }
            Button(action: onSeeAll) {
                Text("SEE ALL")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-wheel-see-all")
        }
        .accessibilityHidden(true)
    }
}
