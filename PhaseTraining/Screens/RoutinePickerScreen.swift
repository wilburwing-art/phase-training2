// RoutinePickerScreen.swift — Browse 167 routines from bundled coach.db.
// Visual reference: design handoff index.html, screens/routine-picker.jsx (variation A).
// Layout follows that variation; type/colors swapped for the existing app's tokens
// (Space Grotesk / electric-lime / paper-white ink).

import SwiftUI

struct RoutinePickerScreen: View {
    let onBack: () -> Void
    let onPick: (Routine) -> Void

    @State private var search: String = ""
    @State private var goalFilter: String? = nil

    private var allRoutines: [Routine] {
        CoachDatabase.shared.listRoutines(
            search: search.isEmpty ? nil : search,
            goal: goalFilter
        )
    }

    private var topGoals: [(String, Int)] {
        Array(CoachDatabase.shared.goalCounts().prefix(6))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        searchField
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        filterChips
                            .padding(.top, 14)

                        sortHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 10)

                        if allRoutines.isEmpty {
                            emptyState
                                .padding(.horizontal, 20)
                                .padding(.top, 60)
                        } else {
                            ForEach(Array(allRoutines.enumerated()), id: \.element.id) { idx, r in
                                routineCard(idx: idx, routine: r)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 12)
                            }
                        }

                        Spacer().frame(height: 60)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Back")
                            .font(.custom("SpaceGrotesk-Medium", size: 15))
                    }
                    .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Routines")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 17))
                    .foregroundStyle(Color.ink)

                Spacer()

                Text("\(allRoutines.count) FOUND")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your library")
                .font(.custom("SpaceGrotesk-SemiBold", size: 38))
                .tracking(-0.03 * 38)
                .foregroundStyle(Color.ink)
            Text("\(CoachDatabase.shared.listRoutines().count) ROUTINES · \(topGoals.count) GOALS · BUNDLED")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.ink3)
            TextField("", text: $search, prompt: Text("Search routines…").foregroundColor(Color.ink3))
                .font(.custom("Inter-Regular", size: 15))
                .foregroundStyle(Color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", count: CoachDatabase.shared.listRoutines().count, active: goalFilter == nil) {
                    goalFilter = nil
                }
                ForEach(topGoals, id: \.0) { goal, count in
                    chip(label: goal.replacingOccurrences(of: "_", with: " ").capitalized,
                         count: count,
                         active: goalFilter == goal) {
                        goalFilter = (goalFilter == goal) ? nil : goal
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(label: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.custom("Inter-Regular", size: 13))
                    .fontWeight(active ? .semibold : .regular)
                Text("\(count)")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .foregroundStyle(active ? Color.accentInk.opacity(0.55) : Color.ink3)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(active ? Color.accent : Color.surface)
            .foregroundStyle(active ? Color.accentInk : Color.ink)
            .overlay(
                Capsule().stroke(active ? Color.accent : Color.line, lineWidth: 0.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort header

    private var sortHeader: some View {
        HStack {
            Text("↓ BY ID")
                .styled(.micro)
                .foregroundStyle(Color.ink2)
            Spacer()
            Text("STACK")
                .styled(.micro)
                .foregroundStyle(Color.ink2)
        }
    }

    // MARK: - Card

    private func routineCard(idx: Int, routine r: Routine) -> some View {
        Button {
            onPick(r)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Top row: split tag + duration
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(splitColor(for: r.splitTag))
                            .frame(width: 8, height: 8)
                        Text(r.splitTag)
                            .font(.custom("JetBrainsMono-Medium", size: 10))
                            .tracking(0.12 * 10)
                            .foregroundStyle(splitColor(for: r.splitTag))
                    }
                    Spacer()
                    Text(durationLabel(r))
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .tracking(0.06 * 10)
                        .foregroundStyle(Color.ink3)
                }
                .padding(.bottom, 12)

                // Title
                Text(r.name)
                    .font(.custom("SpaceGrotesk-SemiBold", size: 22))
                    .tracking(-0.02 * 22)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                // Tag line
                if let desc = subtitle(r) {
                    Text(desc)
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink2)
                        .padding(.top, 4)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                // Stat row
                HStack(alignment: .center, spacing: 18) {
                    statBlock(value: "\(r.exerciseCount)", label: "EX")
                    statBlock(value: "\(r.setCount)", label: "SETS")
                    statBlock(value: r.durationMinutes.map(String.init) ?? "—", label: "MIN")
                    Spacer(minLength: 0)
                    pickPill(active: idx == 0)
                }
                .padding(.top, 14)
                .padding(.vertical, 0)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.line).frame(height: 0.5)
                }
            }
            .padding(18)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("routine-card-\(r.id)")
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.custom("SpaceGrotesk-SemiBold", size: 20))
                .tracking(-0.01 * 20)
                .foregroundStyle(Color.ink)
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 9))
                .tracking(0.12 * 9)
                .foregroundStyle(Color.ink3)
        }
    }

    private func pickPill(active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(active ? "Start" : "Open")
                .font(.custom("SpaceGrotesk-SemiBold", size: 13))
            if active {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(active ? Color.accent : Color.clear)
        .foregroundStyle(active ? Color.accentInk : Color.ink)
        .overlay(
            Capsule().stroke(active ? Color.accent : Color.line, lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No matches")
                .font(.custom("SpaceGrotesk-SemiBold", size: 18))
                .foregroundStyle(Color.ink)
            Text("Try a shorter search or clear the filter.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func subtitle(_ r: Routine) -> String? {
        let parts = [r.goal?.replacingOccurrences(of: "_", with: " ").capitalized,
                     r.difficulty?.capitalized,
                     r.environment?.capitalized]
            .compactMap { $0 }
        return parts.isEmpty ? r.description : parts.joined(separator: " · ")
    }

    private func durationLabel(_ r: Routine) -> String {
        if let m = r.durationMinutes { return "~\(m) MIN" }
        return "—"
    }

    private func splitColor(for tag: String) -> Color {
        switch tag {
        case "UPPER": return Color(red: 0.89, green: 0.53, blue: 0.41)
        case "LOWER": return Color(red: 0.49, green: 0.77, blue: 0.53)
        case "PUSH":  return Color(red: 0.79, green: 0.67, blue: 0.29)
        case "PULL":  return Color(red: 0.42, green: 0.61, blue: 0.81)
        case "COND":  return Color(red: 0.71, green: 0.49, blue: 0.83)
        case "MOB":   return Color(red: 0.64, green: 0.60, blue: 0.52)
        default:      return Color.ink3
        }
    }
}

#Preview("Routine picker") {
    RoutinePickerScreen(onBack: {}, onPick: { _ in })
}
