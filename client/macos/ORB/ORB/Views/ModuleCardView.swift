import SwiftUI

struct ModuleCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let caption: String
    let isOnline: Bool
    let isSelected: Bool
    let accent: Color
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accent.opacity(0.16))
                            .frame(width: 48, height: 48)

                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(accent)
                    }

                    Spacer()

                    Circle()
                        .fill(isOnline ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 11, height: 11)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(caption)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 220, height: 172, alignment: .topLeading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(cardFillColor.opacity(isOnline ? 0.96 : 0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isSelected ? accent : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 18, y: 10)
            .grayscale(isOnline ? 0 : 0.3)
        }
        .buttonStyle(.plain)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color.white
    }
}

struct EmptyStageCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还没有已注册模块")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("等主控上线后，请在维护面板里先注册第一个“曜”或“衡”模块。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: 280, height: 172, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill((colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color.white).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [7, 8]))
                .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.75))
        )
    }
}
