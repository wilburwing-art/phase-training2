//
//  SorenessCheckInPill.swift
//  PhaseTraining
//
//  The app's only entry point to SorenessCheckInSheet.
//
//  Build 122 stripped Today down to the workout, which removed the pill that
//  used to live there. This is its new home on Progress. It sits at
//  ProgressScreen level rather than inside ProgressRecoverySection because
//  that section only renders once a session has been logged, and a soreness
//  check-in does not depend on having trained: a brand-new user is exactly
//  who might log soreness first. Rendered in BOTH the empty and populated
//  branches of Progress. SorenessReachabilityUITests guards that.
//

import SwiftUI

struct SorenessCheckInPill: View {
    @EnvironmentObject private var memoryStore: MemoryStore
    @State private var showSheet: Bool = false

    /// True when memory carries a soreness entry stamped today.
    private var loggedToday: Bool {
        let cal = Calendar.current
        return memoryStore.memory.soreness.contains { cal.isDate($0.date, inSameDayAs: Date()) }
    }

    var body: some View {
        let logged = loggedToday
        Button { showSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: logged ? "checkmark.circle.fill" : "figure.cooldown")
                    .font(.system(size: 13, weight: .semibold))
                Text(logged ? "SORENESS · LOGGED" : "HOW SORE ARE YOU TODAY?")
                    .styled(.micro)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(logged ? Color.accent : Color.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(logged ? Color.accentBorder : Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress-soreness-checkin")
        .sheet(isPresented: $showSheet) {
            SorenessCheckInSheet(onDone: {})
        }
    }
}
