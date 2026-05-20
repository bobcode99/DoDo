//
//  ScrollHeaderCollapseModifier.swift
//  PodcastAnalyzer
//
//  Tracks a ScrollView's content offset/size and hides the host's header
//  when the user scrolls down past a small threshold, restoring it on
//  scroll-up or when near the top. Used by the iOS summary landing page.
//

import SwiftUI

/// Snapshot of scroll geometry values for change detection.
nonisolated struct ScrollGeometrySnapshot: Equatable {
    let contentOffset: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
}

extension View {
    /// Applies header-collapse tracking to a ScrollView. Updates
    /// `isHeaderVisible` based on scroll direction and clamps state when the
    /// content is too short to scroll or the user is at the top/bottom.
    func trackScrollForHeaderCollapse(
        isHeaderVisible: Binding<Bool>,
        lastOffset: Binding<CGFloat>,
        isUserScrolling: Bool
    ) -> some View {
        self
            .onScrollGeometryChange(for: ScrollGeometrySnapshot.self) { geometry in
                ScrollGeometrySnapshot(
                    contentOffset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    visibleHeight: geometry.visibleRect.size.height
                )
            } action: { oldValue, newValue in
                guard isUserScrolling else { return }

                guard newValue.contentHeight > newValue.visibleHeight else {
                    if !isHeaderVisible.wrappedValue { isHeaderVisible.wrappedValue = true }
                    return
                }

                if abs(newValue.contentHeight - oldValue.contentHeight) > 1 {
                    lastOffset.wrappedValue = newValue.contentOffset
                    return
                }

                let nearTopThreshold: CGFloat = 60
                if newValue.contentOffset <= nearTopThreshold {
                    if !isHeaderVisible.wrappedValue {
                        isHeaderVisible.wrappedValue = true
                    }
                    lastOffset.wrappedValue = newValue.contentOffset
                    return
                }

                let maxOffset = newValue.contentHeight - newValue.visibleHeight
                if maxOffset > 0, newValue.contentOffset >= maxOffset - 5 {
                    lastOffset.wrappedValue = newValue.contentOffset
                    return
                }

                let delta = newValue.contentOffset - lastOffset.wrappedValue
                guard abs(delta) > 8 else { return }

                if delta > 0 && isHeaderVisible.wrappedValue {
                    isHeaderVisible.wrappedValue = false
                }
                lastOffset.wrappedValue = newValue.contentOffset
            }
    }
}
