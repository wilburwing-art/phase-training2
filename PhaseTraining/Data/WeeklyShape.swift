// WeeklyShape.swift — lookup tables that map (primarySport × season) onto a
// 7-element ordered list of DayKinds.
//
// Each shape is a *priority-ordered* sequence the Planner walks to fill
// slots after fixed sport days and forced-rest days are placed. The order
// inside the array drives spacing (don't put two heavy lifts back-to-back),
// not weekday alignment.
//
// Resolution falls through in this order:
//   1. (sport, season)        — specific + seasonal
//   2. (sport, .maintenance)  — sport-only fallback
//   3. defaultShape           — 3-day full body if nothing else hits

import Foundation

struct WeeklyShape: Hashable {
    let kinds: [DayKind]      // length 7
    let description: String

    static func resolve(primarySport: Sport?,
                        season: SeasonPhase) -> WeeklyShape {
        if let s = primarySport, let shape = sportSeasonShapes[ShapeKey(sport: s.slug, season: season)] {
            return shape
        }
        if let s = primarySport, let shape = sportSeasonShapes[ShapeKey(sport: s.slug, season: .maintenance)] {
            return shape
        }
        return defaultShape
    }
}

private struct ShapeKey: Hashable {
    let sport: String
    let season: SeasonPhase
}

// MARK: - Default fallback

private let defaultShape = WeeklyShape(
    kinds:       [.lift, .rest, .lift, .rest, .lift, .rest, .rest],
    description: "3-day full body strength — flexible fallback"
)

// MARK: - Sport × season combinations
//
// Each shape encodes ~7 days of intent. The planner uses these as desired
// distribution; user availability + fixed sport days override slots.

private let sportSeasonShapes: [ShapeKey: WeeklyShape] = [

    // Climbing
    ShapeKey(sport: "climbing", season: .inSeason): WeeklyShape(
        kinds:       [.sport, .rest, .lift, .sport, .rest, .rest, .rest],
        description: "Climbing in-season: 2 climbs, 1 lift, 4 rest"),
    ShapeKey(sport: "climbing", season: .preSeason): WeeklyShape(
        kinds:       [.lift, .sport, .rest, .sport, .lift, .rest, .rest],
        description: "Climbing pre-season: 2 climbs, 2 lifts, 3 rest"),
    ShapeKey(sport: "climbing", season: .offSeason): WeeklyShape(
        kinds:       [.lift, .sport, .rest, .lift, .lift, .rest, .rest],
        description: "Climbing off-season: 1 climb, 3 lifts, 3 rest"),
    ShapeKey(sport: "climbing", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .rest, .lift, .sport, .rest, .rest, .rest],
        description: "Climbing maintenance: 2 climbs, 1 lift, 4 rest"),

    // Running
    ShapeKey(sport: "running", season: .inSeason): WeeklyShape(
        kinds:       [.sport, .lift, .rest, .sport, .rest, .sport, .rest],
        description: "Running in-season: 3 runs, 1 lift, 3 rest"),
    ShapeKey(sport: "running", season: .preSeason): WeeklyShape(
        kinds:       [.lift, .sport, .rest, .sport, .lift, .sport, .rest],
        description: "Running pre-season: 3 runs, 2 lifts, 2 rest"),
    ShapeKey(sport: "running", season: .offSeason): WeeklyShape(
        kinds:       [.lift, .sport, .rest, .lift, .sport, .lift, .rest],
        description: "Running off-season: 2 runs, 3 lifts, 2 rest"),
    ShapeKey(sport: "running", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .lift, .rest, .sport, .rest, .lift, .rest],
        description: "Running maintenance: 2 runs, 2 lifts, 3 rest"),
    ShapeKey(sport: "trail-running", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .lift, .rest, .sport, .rest, .lift, .rest],
        description: "Trail running maintenance: 2 runs, 2 lifts, 3 rest"),

    // Cycling
    ShapeKey(sport: "cycling", season: .inSeason): WeeklyShape(
        kinds:       [.sport, .rest, .lift, .sport, .rest, .sport, .rest],
        description: "Cycling in-season: 3 rides, 1 lift, 3 rest"),
    ShapeKey(sport: "cycling", season: .offSeason): WeeklyShape(
        kinds:       [.lift, .sport, .rest, .lift, .sport, .lift, .rest],
        description: "Cycling off-season: 2 rides, 3 lifts, 2 rest"),
    ShapeKey(sport: "cycling", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .rest, .lift, .sport, .rest, .lift, .rest],
        description: "Cycling maintenance: 2 rides, 2 lifts, 3 rest"),

    // Snow sports / skiing
    ShapeKey(sport: "snow-sports", season: .preSeason): WeeklyShape(
        kinds:       [.lift, .rest, .lift, .rest, .rest, .lift, .rest],
        description: "Ski pre-season: 3 lifts, 4 rest (no snow yet)"),
    ShapeKey(sport: "snow-sports", season: .inSeason): WeeklyShape(
        kinds:       [.sport, .rest, .lift, .sport, .rest, .rest, .rest],
        description: "Ski in-season: 2 ski days, 1 lift, 4 rest"),
    ShapeKey(sport: "alpine-skiing", season: .preSeason): WeeklyShape(
        kinds:       [.lift, .rest, .lift, .rest, .rest, .lift, .rest],
        description: "Alpine ski pre-season: 3 lifts, 4 rest"),
    ShapeKey(sport: "alpine-skiing", season: .inSeason): WeeklyShape(
        kinds:       [.sport, .rest, .lift, .sport, .rest, .rest, .rest],
        description: "Alpine ski in-season: 2 ski, 1 lift, 4 rest"),

    // Combat sports — high frequency sport days
    ShapeKey(sport: "bjj", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .lift, .rest, .sport, .rest, .sport, .rest],
        description: "BJJ maintenance: 3 grapples, 1 lift, 3 rest"),
    ShapeKey(sport: "boxing", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .lift, .rest, .sport, .rest, .sport, .rest],
        description: "Boxing maintenance: 3 sessions, 1 lift, 3 rest"),
    ShapeKey(sport: "muay-thai", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .lift, .rest, .sport, .rest, .sport, .rest],
        description: "Muay Thai maintenance: 3 sessions, 1 lift, 3 rest"),

    // Court sports
    ShapeKey(sport: "tennis", season: .inSeason): WeeklyShape(
        kinds:       [.sport, .lift, .rest, .sport, .rest, .sport, .rest],
        description: "Tennis in-season: 3 courts, 1 lift, 3 rest"),
    ShapeKey(sport: "pickleball", season: .maintenance): WeeklyShape(
        kinds:       [.sport, .rest, .lift, .sport, .rest, .sport, .rest],
        description: "Pickleball maintenance: 3 courts, 1 lift, 3 rest"),

    // Strength sports
    ShapeKey(sport: "powerlifting", season: .maintenance): WeeklyShape(
        kinds:       [.lift, .rest, .lift, .rest, .lift, .lift, .rest],
        description: "Powerlifting maintenance: 4 lifts, 3 rest"),
    ShapeKey(sport: "olympic-weightlifting", season: .maintenance): WeeklyShape(
        kinds:       [.lift, .lift, .rest, .lift, .rest, .lift, .rest],
        description: "Oly weightlifting: 4 lifts, 3 rest"),
    ShapeKey(sport: "bodybuilding", season: .maintenance): WeeklyShape(
        kinds:       [.lift, .lift, .rest, .lift, .lift, .lift, .rest],
        description: "Bodybuilding maintenance: 5 lifts, 2 rest"),
    ShapeKey(sport: "crossfit", season: .maintenance): WeeklyShape(
        kinds:       [.lift, .lift, .rest, .lift, .rest, .lift, .rest],
        description: "CrossFit maintenance: 4 lifts, 3 rest"),

    // Mobility-first practices
    ShapeKey(sport: "yoga", season: .maintenance): WeeklyShape(
        kinds:       [.rest, .rest, .rest, .lift, .rest, .rest, .rest],
        description: "Yoga: 1 lift, 6 rest"),
    ShapeKey(sport: "pilates", season: .maintenance): WeeklyShape(
        kinds:       [.rest, .rest, .rest, .lift, .rest, .rest, .rest],
        description: "Pilates: 1 lift, 6 rest"),

    // Multi-sport endurance
    ShapeKey(sport: "obstacle-course-racing", season: .preSeason): WeeklyShape(
        kinds:       [.lift, .sport, .rest, .lift, .sport, .lift, .rest],
        description: "OCR pre-season: 2 sport, 3 lifts, 2 rest")
]
