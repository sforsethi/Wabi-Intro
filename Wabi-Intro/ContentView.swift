//
//  ContentView.swift
//  Wabi-Intro
//
//  Created by Raghav Sethi on 5/5/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        LiquidGlassOnboardingView()
    }
}

private struct LiquidGlassOnboardingView: View {
    var onComplete: () -> Void = {}

    @State private var dragProgress: CGFloat = 0
    @State private var dragStartProgress: CGFloat?
    @State private var dragDirection: DragDirection?
    @State private var dragHaptics = DragHapticDriver()
    @State private var settledDate: Date? = nil
    @State private var didComplete = false

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let bubble = bubbleState(in: size)
                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                liquidGlassBackground(size: size, elapsed: elapsed)
                    .layerEffect(
                        ShaderLibrary.ryceRefractiveGlass(
                            .float2(Float(size.width), Float(size.height)),
                            .float2(Float(bubble.center.x), Float(bubble.center.y)),
                            .float(Float(bubble.radius)),
                            .float(Float(bubble.refraction)),
                            .float(Float(bubble.shadowBlur)),
                            .float(Float(elapsed))
                        ),
                        maxSampleOffset: CGSize(width: bubble.maxSampleOffset, height: bubble.maxSampleOffset)
                    )
                    .contentShape(Rectangle())
                    .gesture(bubbleDragGesture(in: size))
                    .simultaneousGesture(TapGesture().onEnded {
                        withAnimation(.interactiveSpring(response: 1.6, dampingFraction: 0.94)) {
                            dragProgress = dragProgress < 0.5 ? 1 : 0
                        }
                    })
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(alignment: .bottom) {
                    Text("SWIPE UP TO BEGIN")
                        .font(.system(.caption, design: .default, weight: .heavy))
                        .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.3))
                        .offset(y: -abs(sin(elapsed * 1.8)) * 7)
                        .opacity(max(1.0 - dragProgress * 5, 0))
                        .padding(.bottom, 75)
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: dragProgress) { _, newValue in
            if newValue > 0.95 && dragStartProgress == nil {
                if settledDate == nil {
                    settledDate = Date()
                    if !didComplete {
                        didComplete = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                            onComplete()
                        }
                    }
                }
            } else if newValue < 0.5 {
                settledDate = nil
            }
        }
    }

    private func liquidGlassBackground(size: CGSize, elapsed: TimeInterval) -> some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack {
                Text("Welcome")
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .blendMode(.multiply)
                Text("to Wabi")
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .blendMode(.multiply)
            }
            .offset(x: 0, y: 50)

            floatingDishLayer(size: size, elapsed: elapsed)
        }
    }

    private func floatingDishLayer(size: CGSize, elapsed: TimeInterval) -> some View {
        let timeSinceSettled = settledDate.map { Date().timeIntervalSince($0) } ?? 0
        let activeTime = max(timeSinceSettled - 1.5, 0)
        let isActive = timeSinceSettled >= 1.5

        let bubble = bubbleState(in: size)
        let originX = bubble.center.x
        let originY = bubble.center.y + bubble.radius

        return ZStack {
            ForEach(Array(DishEmoji.all.enumerated()), id: \.element.id) { index, dish in
                let stagger = Double(index) * 1.0
                let cycleDuration = 13.0 + Double(index) * 1.0
                let t = max(activeTime - stagger, 0).truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

                let targetX = size.width * (0.08 + 0.84 * (dish.startAngle / (2 * .pi)))
                let x = originX + (targetX - originX) * t + sin(elapsed * 0.18 + dish.startAngle) * size.width * 0.05
                let y = originY + (-70.0 - originY) * t

                let scale = 32.0 / 90.0 + (1.0 - 32.0 / 90.0) * t

                let fadeIn = min(t / 0.08, 1.0)
                let fadeOut = max(1.0 - (t - 0.84) / 0.16, 0.0)

                Text(dish.emoji)
                    .font(.system(size: 90))
                    .scaleEffect(scale)
                    .opacity(isActive ? fadeIn * fadeOut : 0)
                    .position(x: x, y: y)
            }
        }
    }

    private func bubbleDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartProgress == nil {
                    dragStartProgress = dragProgress
                    dragDirection = nil
                    dragHaptics.start()
                }

                if dragDirection == nil, abs(value.translation.height) > 6 {
                    dragDirection = value.translation.height < 0 ? .up : .down
                }

                let travel = max(size.height * 0.48, 1)
                let start = dragStartProgress ?? dragProgress
                dragProgress = min(max(start - value.translation.height / travel, 0), 1)
            }
            .onEnded { _ in
                if let dragDirection {
                    withAnimation(.interactiveSpring(response: 1.45, dampingFraction: 0.94)) {
                        dragProgress = dragDirection == .up ? 1 : 0
                    }
                }

                dragStartProgress = nil
                dragDirection = nil
                dragHaptics.stop()
            }
    }

    private func bubbleState(in size: CGSize) -> BubbleState {
        let expandedRadius = max(size.width * 1.08, 220)
        let collapsedRadius: CGFloat = 68
        let progress = min(max(dragProgress, 0), 1)
        let radius = expandedRadius + (collapsedRadius - expandedRadius) * progress
        let expandedCenter = CGPoint(x: size.width / 2, y: size.height + expandedRadius - 210)
        let collapsedCenter = CGPoint(x: size.width / 2, y: size.height / 2 - 92)
        let center = CGPoint(
            x: expandedCenter.x + (collapsedCenter.x - expandedCenter.x) * progress,
            y: expandedCenter.y + (collapsedCenter.y - expandedCenter.y) * progress
        )

        return BubbleState(
            center: center,
            radius: radius,
            refraction: 1.25,
            shadowBlur: min(max(radius * 0.20, 28), 90),
            maxSampleOffset: max(radius * 2, 240)
        )
    }
}

private enum DragDirection {
    case up
    case down
}

private final class DragHapticDriver {
    private let generator = UIImpactFeedbackGenerator(style: .soft)
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generator.prepare()
        play()
    }

    func stop() {
        isRunning = false
    }

    private func play() {
        guard isRunning else { return }

        generator.impactOccurred(intensity: 0.12)
        generator.prepare()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.085) { [weak self] in
            self?.play()
        }
    }
}

private struct BubbleState {
    let center: CGPoint
    let radius: CGFloat
    let refraction: Double
    let shadowBlur: CGFloat
    let maxSampleOffset: CGFloat
}

private struct DishEmoji: Identifiable {
    let id = UUID()
    let emoji: String
    let radiusXRatio: Double
    let radiusYRatio: Double
    let speed: Double
    let startAngle: Double
    let size: CGFloat
    let delay: TimeInterval
    let breatheSpeed: Double

    static let all: [DishEmoji] = [
        DishEmoji("🍝", 0.34, 0.18, 0.55, 0.1, 48, 0.0, 1.5),
        DishEmoji("🍛", 0.23, 0.31, -0.42, 1.4, 54, 0.1, 1.2),
        DishEmoji("🍜", 0.38, 0.27, 0.35, 2.2, 50, 0.2, 1.8),
        DishEmoji("🥗", 0.18, 0.22, -0.74, 3.5, 47, 0.3, 1.6),
        DishEmoji("🍕", 0.42, 0.14, 0.68, 4.3, 46, 0.4, 1.4),
        DishEmoji("🌮", 0.29, 0.36, -0.31, 5.1, 45, 0.5, 1.9),
        DishEmoji("🍣", 0.14, 0.34, 0.88, 5.9, 44, 0.6, 1.3)
    ]

    init(
        _ emoji: String,
        _ radiusXRatio: Double,
        _ radiusYRatio: Double,
        _ speed: Double,
        _ startAngle: Double,
        _ size: CGFloat,
        _ delay: TimeInterval,
        _ breatheSpeed: Double
    ) {
        self.emoji = emoji
        self.radiusXRatio = radiusXRatio
        self.radiusYRatio = radiusYRatio
        self.speed = speed
        self.startAngle = startAngle
        self.size = size
        self.delay = delay
        self.breatheSpeed = breatheSpeed
    }
}

#Preview {
    ContentView()
}
