import SwiftUI

/// The shared tab area for `EpisodeDetailView` (iOS) and
/// `MacEpisodeDetailView` (macOS): tab selector + tab content + the floating
/// scroll-to-top button + the timestamp popup overlay.
///
/// The hosting view supplies the header above this content and the toolbar /
/// sheets / alerts around it.
struct EpisodeDetailTabsContent: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var selectedTab: Int
    @Binding var isHeaderVisible: Bool
    @Binding var lastScrollOffset: CGFloat
    @Binding var isUserScrolling: Bool
    @Binding var scrollToTopTrigger: Bool

    /// When `true`, scrolling the Summary tab collapses the host's header
    /// (iOS). When `false`, the scroll-to-top button never appears and
    /// scroll geometry is ignored (macOS).
    var enableScrollHeaderCollapse: Bool

    let onShowTranslationLanguagePicker: () -> Void
    let onShowSubtitleSettings: () -> Void
    let onShowRegenerateConfirmation: () -> Void

    @State private var tappedTimestampSeconds: TimeInterval?
    @State private var timestampTapX: CGFloat = 0
    @State private var timestampTapY: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            tabSelector
            Divider()
            tabContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if enableScrollHeaderCollapse && !isHeaderVisible {
                        Button {
                            scrollToTopTrigger.toggle()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .circle)
                        }
                        .padding(.trailing, 12)
                        .padding(.top, 8)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay { timestampPopupOverlay }
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
        }
        // Pin this VStack to its parent's available height. Without it the
        // inner ScrollView's natural content height (a long summary)
        // bubbles up through the custom-View body and grows the parent.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedTab) { _, _ in
            lastScrollOffset = 0
        }
    }

    // MARK: - Tab selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(title: "Summary", isSelected: selectedTab == 0) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 0 }
            }
            TabButton(title: "Transcript", isSelected: selectedTab == 1) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 1 }
            }
            TabButton(title: "AI", isSelected: selectedTab == 2) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 2 }
            }
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContentView: some View {
        switch selectedTab {
        case 0: summaryTab
        case 1: TranscriptContentView(
            viewModel: viewModel,
            isHeaderVisible: $isHeaderVisible,
            lastScrollOffset: $lastScrollOffset,
            isUserScrolling: $isUserScrolling,
            scrollToTopTrigger: $scrollToTopTrigger,
            onShowTranslationPicker: onShowTranslationLanguagePicker,
            onShowSubtitleSettings: onShowSubtitleSettings,
            onShowRegenerateConfirmation: onShowRegenerateConfirmation
        )
        case 2: EpisodeAIAnalysisView(
            viewModel: viewModel,
            embedsOwnScroll: true,
            isHeaderVisible: $isHeaderVisible,
            lastScrollOffset: $lastScrollOffset,
            isUserScrolling: $isUserScrolling,
            scrollToTopTrigger: $scrollToTopTrigger
        )
        default:
            Text("Unknown tab: \(selectedTab)")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary tab

    private var summaryTab: some View {
        ScrollViewReader { proxy in
            let scrollContent = ScrollView {
                Color.clear.frame(height: 0).id("summaryTop")
                summaryContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded {
                        timestampTapX = $0.location.x
                        timestampTapY = $0.location.y
                    }
            )
            .onScrollPhaseChange { _, newPhase in
                isUserScrolling = newPhase == .interacting || newPhase == .decelerating
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("summaryTop", anchor: .top)
                }
                isHeaderVisible = true
            }

            if enableScrollHeaderCollapse {
                scrollContent.trackScrollForHeaderCollapse(
                    isHeaderVisible: $isHeaderVisible,
                    lastOffset: $lastScrollOffset,
                    isUserScrolling: isUserScrolling
                )
            } else {
                scrollContent
            }
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let translated = viewModel.translatedDescription {
                VStack(alignment: .leading, spacing: 12) {
                    HTMLTextView(
                        attributedString: NSAttributedString(
                            TimestampUtils.attributedStringWithTimestampLinks(translated)
                        )
                    )

                    Divider()

                    DisclosureGroup("Original") {
                        descriptionView
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    descriptionView
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if let seconds = TimestampUtils.parseTimestampURL(url) {
                tappedTimestampSeconds = seconds
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private var descriptionView: some View {
        switch viewModel.descriptionContent {
        case .loading:
            Text("Loading...").foregroundStyle(.secondary)
        case .empty:
            Text("No description available.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .parsed(let attributedString):
            HTMLTextView(attributedString: attributedString, linkTimestamps: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Timestamp popup overlay

    @ViewBuilder
    private var timestampPopupOverlay: some View {
        if let seconds = tappedTimestampSeconds {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { tappedTimestampSeconds = nil }
                .overlay {
                    GeometryReader { geo in
                        let popupWidth: CGFloat = 240
                        let popupHeight: CGFloat = 110
                        let x = min(
                            max(timestampTapX, popupWidth / 2 + 16),
                            geo.size.width - popupWidth / 2 - 16
                        )
                        let showAbove = timestampTapY > geo.size.height - popupHeight - 60
                        let y = showAbove
                            ? timestampTapY - popupHeight / 2 - 10
                            : timestampTapY + popupHeight / 2 + 10

                        TimestampPopup(
                            seconds: seconds,
                            onPlay: {
                                viewModel.seekToTime(seconds)
                                tappedTimestampSeconds = nil
                            },
                            onShare: {
                                viewModel.shareTimestampedLink(seconds: seconds)
                                tappedTimestampSeconds = nil
                            }
                        )
                        .position(x: x, y: y)
                        .transition(
                            .scale(scale: 0.88, anchor: showAbove ? .bottom : .top)
                            .combined(with: .opacity)
                        )
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: tappedTimestampSeconds != nil)
        }
    }
}

// MARK: - Scroll header collapse modifier (iOS only by host opt-in)

/// Snapshot of scroll geometry values for change detection.
nonisolated struct ScrollGeometrySnapshot: Equatable {
    let contentOffset: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
}

extension View {
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
