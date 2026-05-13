// RoutineDetailScreen.swift — Preview a routine before starting; tweak in-session.
// Reference: design handoff workout-swipe.jsx. SwiftUI `.swipeActions` replaces
// the JSX hand-rolled translate-X swipe. Edits are in-memory only (coach.db stays
// read-only); the modified list is what gets converted into the ActiveSession.

import SwiftUI

struct RoutineDetailScreen: View {
    let routine: Routine
    @Binding var exercises: [RoutineExercise]

    let onBack: () -> Void
    let onStart: () -> Void
    let onTapExercise: (RoutineExercise) -> Void
    let onAddExercise: () -> Void
    let onReplaceExercise: (Int) -> Void

    private var setCount: Int { exercises.compactMap(\.sets).reduce(0, +) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        hintBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        sectionHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 10)

                        LazyVStack(spacing: 6) {
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                                rowCard(idx: idx, ex: ex)
                                    .padding(.horizontal, 20)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            exercises.remove(at: idx)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            onReplaceExercise(idx)
                                        } label: {
                                            Label("Replace", systemImage: "arrow.left.arrow.right")
                                        }
                                        .tint(Color(red: 0.10, green: 0.10, blue: 0.15))
                                    }
                            }
                        }

                        addButton
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        Spacer().frame(height: 140)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            startButton
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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
                        Text("Routines")
                            .font(.custom("SpaceGrotesk-Medium", size: 15))
                    }
                    .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Edit routine")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 17))
                Spacer()
                Text("DONE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROUTINE · \(exercises.count) EX · \(setCount) SETS")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text(routine.name)
                .font(.custom("SpaceGrotesk-SemiBold", size: 32))
                .tracking(-0.02 * 32)
                .foregroundStyle(Color.ink)
            if let sub = subtitle {
                Text(sub)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink2)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String? {
        [routine.goal, routine.difficulty, routine.environment]
            .compactMap { $0?.replacingOccurrences(of: "_", with: " ").capitalized }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    // MARK: - Hint banner

    private var hintBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accent)
            Text("Swipe an exercise to ")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.ink)
            + Text("replace")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.accent)
            + Text(" or ")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.ink)
            + Text("delete.")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.danger)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack {
            Text("EXERCISES")
                .styled(.micro)
                .foregroundStyle(Color.ink)
            Spacer()
            Text("TAP TO VIEW")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
        }
    }

    // MARK: - Row

    private func rowCard(idx: Int, ex: RoutineExercise) -> some View {
        Button { onTapExercise(ex) } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(String(format: "%02d", idx + 1))
                    .font(.custom("JetBrainsMono-Regular", size: 11))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 22, alignment: .trailing)

                VStack(alignment: .leading, spacing: 5) {
                    Text(ex.name)
                        .font(.custom("SpaceGrotesk-SemiBold", size: 17))
                        .tracking(-0.01 * 17)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(rowMeta(ex))
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .tracking(0.05 * 10)
                        .foregroundStyle(Color.ink2)
                        .textCase(.uppercase)
                }
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func rowMeta(_ ex: RoutineExercise) -> String {
        var parts: [String] = []
        if let s = ex.sets { parts.append("\(s) SETS") }
        if let r = ex.reps, !r.isEmpty { parts.append(r.uppercased()) }
        if let rest = ex.rest, !rest.isEmpty { parts.append("\(rest.uppercased()) REST") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Add button

    private var addButton: some View {
        Button(action: onAddExercise) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.ink2, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink2)
                }
                Text("ADD EXERCISE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink2)
                Spacer()
            }
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .foregroundStyle(Color.line)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 6) {
                Text("Start workout")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(exercises.isEmpty)
        .opacity(exercises.isEmpty ? 0.4 : 1)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
