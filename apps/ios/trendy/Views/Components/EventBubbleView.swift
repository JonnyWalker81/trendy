//
//  EventBubbleView.swift
//  trendy
//
//  Created by Jonathan Rothberg on 7/18/25.
//

import SwiftUI

struct EventBubbleView: View {
    let eventType: EventType
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @State private var isPressed = false
    @State private var showingCheckmark = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(eventType.color.gradient)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .shadow(color: eventType.color.opacity(0.3), radius: isPressed ? 5 : 10)
                
                Image(systemName: eventType.iconName)
                    .font(.system(size: 35))
                    .foregroundColor(.white)
                    .scaleEffect(showingCheckmark ? 0 : 1)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 35))
                    .foregroundColor(.white)
                    .scaleEffect(showingCheckmark ? 1 : 0)
                    .opacity(showingCheckmark ? 1 : 0)
            }
            
            Text(eventType.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
                showingCheckmark = true
            }
            
            onTap()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                    showingCheckmark = false
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            onLongPress()
        }
        .accessibilityIdentifier("eventBubble_\(eventType.id)")
    }
}