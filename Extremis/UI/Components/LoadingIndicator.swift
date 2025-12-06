// MARK: - Loading Indicator
// Reusable loading indicator component

import SwiftUI

/// Loading indicator with different styles
struct LoadingIndicator: View {
    enum Style {
        case spinning
        case dots
        case pulse
    }
    
    let style: Style
    var color: Color = .accentColor
    var size: CGFloat = 20
    
    var body: some View {
        switch style {
        case .spinning:
            SpinningIndicator(color: color, size: size)
        case .dots:
            DotsIndicator(color: color, size: size)
        case .pulse:
            PulseIndicator(color: color, size: size)
        }
    }
}

// MARK: - Spinning Indicator

struct SpinningIndicator: View {
    let color: Color
    let size: CGFloat
    
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, lineWidth: 2)
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Dots Indicator

struct DotsIndicator: View {
    let color: Color
    let size: CGFloat
    
    @State private var currentIndex = 0
    let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .scaleEffect(currentIndex == index ? 1.3 : 1.0)
                    .opacity(currentIndex == index ? 1.0 : 0.5)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                currentIndex = (currentIndex + 1) % 3
            }
        }
    }
}

// MARK: - Pulse Indicator

struct PulseIndicator: View {
    let color: Color
    let size: CGFloat
    
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Preview

struct LoadingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            LoadingIndicator(style: .spinning)
            LoadingIndicator(style: .dots)
            LoadingIndicator(style: .pulse)
        }
        .padding()
    }
}

