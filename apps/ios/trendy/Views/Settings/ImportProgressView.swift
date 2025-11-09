//
//  ImportProgressView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct ImportProgressView: View {
    @State private var progress: Double = 0.0
    @State private var currentAction = "Preparing import..."
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)
                
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(
                            Animation.linear(duration: 2)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                    
                    Text("\(Int(progress * 100))%")
                        .font(.headline)
                }
            }
            
            VStack(spacing: 8) {
                Text("Importing Events")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(currentAction)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            Spacer()
        }
        .onAppear {
            isAnimating = true
            simulateProgress()
        }
    }
    
    private func simulateProgress() {
        let actions = [
            "Fetching calendar events...",
            "Analyzing event types...",
            "Creating new categories...",
            "Importing events...",
            "Finalizing import..."
        ]
        
        var currentStep = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            withAnimation {
                progress = min(1.0, progress + 0.1)
                
                let actionIndex = Int(progress * Double(actions.count - 1))
                if actionIndex != currentStep && actionIndex < actions.count {
                    currentStep = actionIndex
                    currentAction = actions[actionIndex]
                }
                
                if progress >= 1.0 {
                    timer.invalidate()
                    currentAction = "Import complete!"
                }
            }
        }
    }
}