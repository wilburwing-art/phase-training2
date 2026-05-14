import SwiftUI

struct TabPlaceholder: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                Spacer()
                Text(eyebrow)
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                Text(title)
                    .font(.custom("SpaceGrotesk-SemiBold", size: 38))
                    .tracking(-0.025 * 38)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        }
    }
}
