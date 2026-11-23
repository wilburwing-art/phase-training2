// PlacesSheet.swift — Profile > Places: the places the app learned from where
// workouts started, a delete for each, a delete-all, and the capture off
// switch (SessionLocationCapture.captureOffKey). Everything stays on device.

import SwiftUI

struct PlacesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var planStore: PlanStore
    @AppStorage(SessionLocationCapture.captureOffKey) private var captureOff = false
    @State private var placePendingDelete: TrainingPlace?
    @State private var confirmingDeleteAll = false

    var body: some View {
        let places = PlaceClusterer.cluster(planStore.sessionPlaces)
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CAPTURE")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        Toggle(isOn: Binding(get: { !captureOff }, set: { captureOff = !$0 })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remember where workouts start")
                                    .styled(.body)
                                    .foregroundStyle(Color.ink)
                                Text("One rough location (about 100 m) when a workout starts. Stays on this phone.")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.ink3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Color.accent)
                        .accessibilityIdentifier("places-capture-toggle")
                        if captureOff {
                            Text("Off. Places already saved stay until you delete them.")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                        }

                        Text("PLACES")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 8)
                        if planStore.sessionPlaces.isEmpty {
                            Text("No places yet. A place appears after a workout starts with location allowed.")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(places) { place in
                            placeRow(place)
                        }

                        if !planStore.sessionPlaces.isEmpty {
                            Button(role: .destructive) {
                                confirmingDeleteAll = true
                            } label: {
                                Text("Delete all saved locations")
                                    .styled(.body)
                                    .foregroundStyle(Color.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                            .accessibilityIdentifier("places-delete-all")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            placePendingDelete.map { "Delete Place \($0.id + 1)?" } ?? "Delete place?",
            isPresented: Binding(get: { placePendingDelete != nil },
                                 set: { if !$0 { placePendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: placePendingDelete
        ) { place in
            Button("Delete", role: .destructive) {
                planStore.deleteSessionPlaces(sessionIds: Set(place.sessionIds))
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its saved locations are removed from this phone.")
        }
        .confirmationDialog("Delete all saved locations?",
                            isPresented: $confirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                planStore.deleteAllSessionPlaces()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every saved workout start location is removed from this phone.")
        }
    }

    private func placeRow(_ place: TrainingPlace) -> some View {
        let name = "Place \(place.id + 1)"
        let noun = place.visitCount == 1 ? "workout" : "workouts"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Text("\(place.visitCount) \(noun) · last \(place.lastSeen.formatted(date: .abbreviated, time: .omitted))")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                Text(String(format: "%.3f, %.3f", place.latitude, place.longitude))
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 8)
            Button {
                placePendingDelete = place
            } label: {
                Image(systemName: "trash")
                    .scaledSystemFont(18)
                    .foregroundStyle(Color.ink3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(name)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineStrong, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
