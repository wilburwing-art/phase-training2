// TabHeader.swift — the unified tab chrome.
//
// One primitive across all five tabs. Replaces five forked custom-top-bar +
// hero stacks (Library, Today, Progress, Complete, CoachRequest) with a
// single layout: micro eyebrow row + 0.5px divider + displayL title + body
// subtitle + optional sparkle-prefixed caption.
//
// Spec ref: HANDOFF-tile-system.md §3 — do not deviate per tab.
// Tokens come from Theme/Theme.swift and Theme/Typography.swift.

import SwiftUI

struct TabHeader: View {
    let eyebrow: String           // e.g. "WED · MAY 20" — uppercased upstream
    let eyebrowTrailing: String?  // e.g. "6 EX · 22 SETS"
    let title: String             // \n-separated for multi-line
    let subtitle: String?
    let caption: String?          // optional sparkle-prefixed insight line

    init(
        eyebrow: String,
        eyebrowTrailing: String? = nil,
        title: String,
        subtitle: String? = nil,
        caption: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.eyebrowTrailing = eyebrowTrailing
        self.title = title
        self.subtitle = subtitle
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step 1: top pad 12 under status bar
            Color.clear.frame(height: 12)

            // Step 2: HStack eyebrow left / eyebrowTrailing right
            HStack {
                Text(eyebrow)
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer(minLength: 0)
                if let eyebrowTrailing {
                    Text(eyebrowTrailing)
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }

            // Step 3: gap 8, then 0.5px divider
            Color.clear.frame(height: 8)
            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)

            // Step 4: content top pad 24
            Color.clear.frame(height: 24)

            // Step 5: title (displayL · ink · lineSpacing(-2))
            Text(title)
                .styled(.displayL)
                .foregroundStyle(Color.ink)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)

            // Step 6: gap 6, subtitle (body · ink2)
            if let subtitle {
                Color.clear.frame(height: 6)
                Text(subtitle)
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Step 7: optional caption — gap 10, sparkle (10pt accent) + JBMono 11 ink3
            if let caption {
                Color.clear.frame(height: 10)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accent)
                    Text(caption)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        // One logical header for VoiceOver — eyebrow, title, subtitle, and
        // caption read as a single element instead of four swipe stops.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview — five tab use cases

#Preview("Tab headers") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {

            // 1. Today — full chrome (eyebrow trailing, multi-line title, subtitle, caption)
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 20)
                TabHeader(
                    eyebrow: "WED · MAY 20",
                    eyebrowTrailing: "6 EX · 22 SETS",
                    title: "Upper\nstrength",
                    subtitle: "Push focus · 55 min target",
                    caption: "PR window open on bench — prior 4×6 @ 185"
                )
            }

            // 2. Library — eyebrow with count, single-line title, subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("LIBRARY")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 20)
                TabHeader(
                    eyebrow: "LIBRARY",
                    eyebrowTrailing: "142 EX · 8 ROUTINES",
                    title: "Library",
                    subtitle: "Browse every exercise and routine."
                )
            }

            // 3. Progress — single eyebrow, single title, no subtitle, caption
            VStack(alignment: .leading, spacing: 8) {
                Text("PROGRESS")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 20)
                TabHeader(
                    eyebrow: "PROGRESS · 12 WK",
                    eyebrowTrailing: nil,
                    title: "Volume up\n12% this block",
                    subtitle: nil,
                    caption: "3 PRs in the last 14 days"
                )
            }

            // 4. Complete — eyebrow only, multi-line title, subtitle
            VStack(alignment: .leading, spacing: 8) {
                Text("COMPLETE")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 20)
                TabHeader(
                    eyebrow: "WED · MAY 20",
                    eyebrowTrailing: "54 MIN",
                    title: "Workout\nlogged",
                    subtitle: "6 exercises · 22 sets · 1 PR"
                )
            }

            // 5. Coach request — minimal chrome
            VStack(alignment: .leading, spacing: 8) {
                Text("COACH REQUEST")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 20)
                TabHeader(
                    eyebrow: "COACH",
                    eyebrowTrailing: nil,
                    title: "Generated\nplan",
                    subtitle: "Review before adding to your week."
                )
            }
        }
        .padding(.bottom, 40)
    }
    .background(Color.bg.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
