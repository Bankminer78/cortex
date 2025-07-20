import SwiftUI

struct WebsiteBlockingView: View {
    let domains: [String]
    let message: String
    let allowOverride: Bool
    let onOverride: () -> Void
    let onDismiss: () -> Void
    
    @State private var showConfirmation = false
    
    var body: some View {
        ZStack {
            // Dark overlay background
            Rectangle()
                .fill(Color.black.opacity(0.95))
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Shield icon and title
                VStack(spacing: 20) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Website Blocked")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Blocked domains list
                VStack(spacing: 12) {
                    ForEach(domains, id: \.self) { domain in
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.red)
                            Text(domain)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                
                // Message
                Text(message)
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 20) {
                    if allowOverride {
                        // Override button (easy to access)
                        Button("Override Block") {
                            showConfirmation = true
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.orange)
                        )
                    }
                    
                    // Dismiss button
                    Button("Stay Focused") {
                        onDismiss()
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.blue)
                    )
                }
                .padding(.bottom, 60)
            }
        }
        .onKeyPress(.escape) {
            if allowOverride {
                showConfirmation = true
            }
            return .handled
        }
        .alert("Override Website Block?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, Override") {
                onOverride()
            }
        } message: {
            Text("Are you sure you want to override the block and access \(domains.joined(separator: ", "))? This will disable the protective shield.")
        }
    }
}

#Preview {
    WebsiteBlockingView(
        domains: ["instagram.com", "www.instagram.com"],
        message: "Instagram is temporarily blocked to help you stay focused. Take this time to engage in a more mindful activity.",
        allowOverride: true,
        onOverride: {},
        onDismiss: {}
    )
} 