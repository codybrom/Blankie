//
//  ExpandableSection.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI

struct ExpandableSection<Content: View>: View {
  let title: String
  @Binding var isExpanded: Bool
  let onExpand: () -> Void
  let content: Content
  @State private var isHovering = false

  init(
    title: String,
    isExpanded: Binding<Bool>,
    onExpand: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
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
              .font(.aboutHeading)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.secondary)
              .imageScale(.small)
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
              .accessibilityHidden(true)
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
        .handCursor()
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Collapses this section" : "Expands this section"))
        .onHover { hovering in
          isHovering = hovering
        }

        // Expanded Content
        if isExpanded {
          Divider()
            .padding(.horizontal, -8)
            .accessibilityHidden(true)

          content
            .padding(.top, 12)
            .padding(.horizontal, 4)
        }
      }
    }
  }
}
