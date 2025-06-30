//
//  ExpandableSection.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

struct ExpandableSection<Content: View>: View {
  let title: String
  let comment: String
  @Binding var isExpanded: Bool
  let onExpand: () -> Void
  let content: Content
  @State private var isHovering = false

  init(
    title: String,
    comment: String,
    isExpanded: Binding<Bool>,
    onExpand: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.comment = comment
    self._isExpanded = isExpanded
    self.onExpand = onExpand
    self.content = content()
  }

  var body: some View {
    GroupBox {
      VStack(spacing: 0) {
        // Header Button
        Button(action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if !isExpanded {
              onExpand()  // Close other sections
            }
            isExpanded.toggle()
          }
        }) {
          HStack {
            Text(title)
              .font(.system(size: 13, weight: .bold))
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.secondary)
              .imageScale(.small)
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .padding(.horizontal, 4)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          isHovering = hovering
          #if os(macOS)
            if hovering {
              NSCursor.pointingHand.push()
            } else {
              NSCursor.pop()
            }
          #endif
        }

        // Expanded Content
        if isExpanded {
          Divider()
            .padding(.horizontal, -8)

          content
            .padding(.top, 12)
            .padding(.horizontal, 4)
        }
      }
    }
  }
}
