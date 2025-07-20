import SwiftUI

struct MotivationalLockScreenView: View {
    let title: String
    let message: String
    let backgroundColor: String
    let emojiIcon: String
    let allowOverride: Bool
    let duration: TimeInterval
    let onDismiss: () -> Void
    
    @State private var showOverrideButton = false
    
    init(title: String, message: String, backgroundColor: String, emojiIcon: String, allowOverride: Bool, duration: TimeInterval, onDismiss: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.backgroundColor = backgroundColor
        self.emojiIcon = emojiIcon
        self.allowOverride = allowOverride
        self.duration = duration
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack {
            // Beautiful gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: backgroundColor) ?? Color.pink.opacity(0.3),
                    Color(hex: backgroundColor)?.opacity(0.6) ?? Color.pink.opacity(0.6),
                    Color(hex: backgroundColor)?.opacity(0.4) ?? Color.pink.opacity(0.4)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Large emoji icon with gentle animation
                Text(emojiIcon)
                    .font(.system(size: 120))
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: UUID())
                
                // Title
                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                
                // LLM-generated motivational message
                Text(message)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .lineLimit(nil)
                
                // Simple exit button
                Button(action: onDismiss) {
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                        Text("Exit Focus Mode")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(.white.opacity(0.2))
                            .stroke(.white.opacity(0.4), lineWidth: 1.5)
                    )
                }
                
                Spacer()
                
                // Override button (if allowed)
                if allowOverride {
                    VStack(spacing: 16) {
                        if !showOverrideButton {
                            Button("I really need to get back") {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showOverrideButton = true
                                }
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                        } else {
                            HStack(spacing: 20) {
                                Button("Stay Focused") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showOverrideButton = false
                                    }
                                }
                                .buttonStyle(MotivationalButtonStyle(isPrimary: true))
                                
                                Button("End Focus Time") {
                                    onDismiss()
                                }
                                .buttonStyle(MotivationalButtonStyle(isPrimary: false))
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .padding()
        }
    }
}

// Custom button style for the lock screen
struct MotivationalButtonStyle: ButtonStyle {
    let isPrimary: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(isPrimary ? .white : .white.opacity(0.9))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(isPrimary ? .white.opacity(0.3) : .clear)
                    .stroke(.white.opacity(0.5), lineWidth: isPrimary ? 0 : 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Helper extension for hex colors
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    MotivationalLockScreenView(
        title: "✨ Focus Time",
        message: "You've got this! Take a deep breath and remember what you're working toward. This moment is a chance to realign with your goals.",
        backgroundColor: "#FFB6C1",
        emojiIcon: "😊",
        allowOverride: true,
        duration: 300, // Still needed for config but not used for timer
        onDismiss: {}
    )
} 