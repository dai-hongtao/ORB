import AppKit
import QuartzCore
import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var displayedModuleIDs: [Int] = []
    @State private var draggedModuleID: Int?
    @State private var dragTranslation: CGSize = .zero
    @State private var sourceSettingsVisible = false
    @State private var hoveredHotspot: OverviewHotspot?
    @State private var activeRadianceTarget: RadianceDropTarget?
    @State private var activeBalanceTarget: BalanceDropTarget?
    @State private var selectedMetricTokenIDs: Set<String> = []
    @Namespace private var metricTokenNamespace

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ModuleOverviewView(
                displayedModuleIDs: $displayedModuleIDs,
                draggedModuleID: $draggedModuleID,
                dragTranslation: $dragTranslation,
                sourceSettingsVisible: $sourceSettingsVisible,
                hoveredHotspot: $hoveredHotspot,
                activeRadianceTarget: $activeRadianceTarget,
                activeBalanceTarget: $activeBalanceTarget,
                selectedMetricTokenIDs: $selectedMetricTokenIDs,
                metricTokenNamespace: metricTokenNamespace
            )

            connectionButton
                .padding(22)

            if let message = appModel.moduleActionNotice ?? appModel.moduleActionIssue {
                Text(message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(appModel.moduleActionIssue == nil ? Color.green : Color.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 58)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity)
                    .zIndex(18)
            }

            if !appModel.showingMaintenanceScreen {
                NewDeviceMainOverlay()
                    .environmentObject(appModel)
                    .padding(.top, 92)
                    .padding(.trailing, 24)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .zIndex(16)
            }

            if appModel.showingMaintenanceScreen {
                DeveloperSettingsOverlay()
                    .transition(.opacity)
                    .zIndex(20)
            }

            if let issue = appModel.localNetworkAccessIssue {
                LocalNetworkAccessBanner(message: issue)
                    .environmentObject(appModel)
                    .padding(.top, 22)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(24)
            }

            if appModel.shouldShowLocalNetworkPrimer {
                LocalNetworkPrimerOverlay()
                    .environmentObject(appModel)
                    .transition(.opacity)
                    .zIndex(30)
            }
        }
        .coordinateSpace(name: "overview")
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowAccessor { window in
            appModel.attachMainWindow(window)
        })
        .task {
            if !appModel.shouldShowLocalNetworkPrimer {
                appModel.bootstrap()
            }
            syncDisplayedModuleIDs()
        }
        .onChange(of: appModel.orderedModules.map(\.id)) { _, _ in
            if draggedModuleID == nil {
                syncDisplayedModuleIDs()
            }
        }
        .onChange(of: appModel.refreshInterval) { _, _ in
            appModel.handleRefreshIntervalChanged()
        }
        .onChange(of: appModel.moduleActionNotice ?? appModel.moduleActionIssue) { _, message in
            appModel.scheduleModuleActionMessageDismiss(for: message)
        }
        .sheet(item: $appModel.activeCalibration) { _ in
            CalibrationSheetView()
                .environmentObject(appModel)
        }
        .animation(.easeOut(duration: 0.22), value: activeRadianceTarget)
        .animation(.easeOut(duration: 0.22), value: activeBalanceTarget)
        .animation(.easeOut(duration: 0.22), value: appModel.showingMaintenanceScreen)
    }

    private var connectionButton: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appModel.connectionStatus == .online ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .shadow(color: (appModel.connectionStatus == .online ? Color.green : Color.clear).opacity(0.55), radius: 5)

            Text(appModel.connectionStatusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Button {
                appModel.reconnectFromStatusBadge()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(StatusBadgeRefreshButtonStyle())
            .foregroundStyle(.secondary)
            .focusEffectDisabled()
            .help("手动重连")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .help(appModel.connectionStatusHelpText)
    }

    private func syncDisplayedModuleIDs() {
        displayedModuleIDs = appModel.orderedModules.map(\.id)
    }
}

private struct StatusBadgeRefreshButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.001))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct LocalNetworkAccessBanner: View {
    @EnvironmentObject private var appModel: AppModel
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Button("打开系统设置") {
                appModel.openLocalNetworkSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 620)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LocalNetworkPrimerOverlay: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.26)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text("允许 ORB 访问本地网络")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                Text("ORB 需要在局域网中发现并连接设备你的设备。点击继续后，macOS 会弹出系统授权窗口，请选择“允许”。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("继续") {
                        appModel.beginLocalNetworkAccessFlow()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(width: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        }
    }
}

private struct NewDeviceMainOverlay: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        if let selectedUnknownAddress = appModel.selectedUnknownAddress {
            registrationPanel(for: selectedUnknownAddress)
        } else if let firstUnknownAddress = appModel.unknownDeviceAddresses.first {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    appModel.selectUnknownDevice(firstUnknownAddress)
                }
            } label: {
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.035))
                        .frame(width: 96, height: 118)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.3, dash: [6, 5]))
                        )
                        .overlay(
                            Text("?")
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        )

                    Text("发现新设备")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .help("注册新设备")
        }
    }

    @ViewBuilder
    private func registrationPanel(for selectedUnknownAddress: Int) -> some View {
        if appModel.selectedUnknownDeviceNeedsReset() {
            UnknownDeviceResetView(
                addressLabel: appModel.selectedUnknownAddressLabel,
                issueText: appModel.unknownDeviceIssue,
                isResetting: appModel.isPerformingUnknownDeviceAction,
                cancelAction: appModel.dismissUnknownDeviceFlow,
                resetAction: appModel.resetSelectedUnknownDevice
            )
            .frame(width: 390, height: 330)
        } else {
            UnknownDeviceRegistrationView(
                moduleType: $appModel.pendingUnknownModuleType,
                moduleID: $appModel.pendingUnknownModuleID,
                validIDs: appModel.validRegistrationIDs(for: selectedUnknownAddress),
                noticeText: appModel.unknownDeviceNotice,
                issueText: appModel.unknownDeviceIssue,
                isRegistering: appModel.isPerformingUnknownDeviceAction,
                cancelAction: appModel.dismissUnknownDeviceFlow,
                registerAction: appModel.registerSelectedUnknownDevice
            )
            .frame(width: 390, height: 330)
        }
    }

    private func rawAddressLabel(_ address: Int) -> String {
        String(format: "I2C 0x%02X", address)
    }
}

private struct ModuleOverviewView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var dragStartCenter: CGPoint?
    @Binding var displayedModuleIDs: [Int]
    @Binding var draggedModuleID: Int?
    @Binding var dragTranslation: CGSize
    @Binding var sourceSettingsVisible: Bool
    @Binding var hoveredHotspot: OverviewHotspot?
    @Binding var activeRadianceTarget: RadianceDropTarget?
    @Binding var activeBalanceTarget: BalanceDropTarget?
    @Binding var selectedMetricTokenIDs: Set<String>
    let metricTokenNamespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            let layout = overviewLayout(in: proxy.size)
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) {
                            sourceSettingsVisible = false
                            activeRadianceTarget = nil
                            activeBalanceTarget = nil
                            selectedMetricTokenIDs = []
                        }
                    }

                if !hasConnectedSource {
                    Text("请将「源」模块连接至WiFi。")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    sourceModule(layout: layout)

                    ForEach(orderedEntriesForDisplay) { entry in
                        moduleView(for: entry, layout: layout)
                    }

                    globalInteractionLayer(layout: layout)

                    if sourceSettingsVisible {
                        SourceInlineSettingsView(refreshInterval: $appModel.refreshInterval)
                            .environmentObject(appModel)
                            .frame(width: layout.sourceSettingsWidth)
                            .position(x: layout.sourceCenter.x, y: layout.sourceSettingsY)
                            .transition(.opacity)
                            .zIndex(12)
                    }

                    if let activeRadianceTarget {
                        if let entry = orderedEntriesForDisplay.first(where: { $0.id == activeRadianceTarget.moduleID }) {
                            TubeActionButtons(entry: entry, channelIndex: activeRadianceTarget.channelIndex)
                                .environmentObject(appModel)
                                .position(layout.radianceActionBarCenter(for: activeRadianceTarget, assignedHeight: assignedStackHeight(for: entry, channelIndex: activeRadianceTarget.channelIndex)))
                                .transition(.opacity)
                                .zIndex(13)
                        }

                        MetricCandidatePanel(
                            tokens: availableMetricTokens,
                            selectedTokenIDs: $selectedMetricTokenIDs,
                            dropZones: layout.radianceDropZones,
                            columnCount: layout.candidatePanelColumnCount,
                            activeTarget: activeRadianceTarget,
                            assignTokens: assignMetricTokens,
                            metricTokenNamespace: metricTokenNamespace
                        )
                        .frame(width: layout.candidatePanelSize.width, height: layout.candidatePanelSize.height)
                        .position(layout.candidatePanelCenter(for: activeRadianceTarget, assignedHeight: assignedStackHeight(for: orderedEntriesForDisplay.first(where: { $0.id == activeRadianceTarget.moduleID }), channelIndex: activeRadianceTarget.channelIndex)))
                        .transition(.opacity)
                        .zIndex(12)
                    }

                    if let activeBalanceTarget {
                        if let entry = orderedEntriesForDisplay.first(where: { $0.id == activeBalanceTarget.moduleID }) {
                            TubeActionButtons(
                                entry: entry,
                                channelIndex: activeBalanceTarget.channelIndex,
                                importAction: {
                                    appModel.importBalanceGaugeSettings(for: entry, channelIndex: activeBalanceTarget.channelIndex)
                                }
                            )
                            .environmentObject(appModel)
                            .position(layout.balanceActionBarCenter(for: activeBalanceTarget))
                            .transition(.opacity)
                            .zIndex(13)
                        }

                        BalanceCandidatePanel(
                            tokens: availableBalanceTokens,
                            dropZones: layout.balanceHotspots,
                            activeTarget: activeBalanceTarget,
                            assignToken: assignBalanceMetricToken,
                            metricTokenNamespace: metricTokenNamespace
                        )
                        .frame(width: layout.balanceCandidatePanelSize.width, height: layout.balanceCandidatePanelSize.height)
                        .position(layout.balanceCandidatePanelCenter(for: activeBalanceTarget))
                        .transition(.opacity)
                        .zIndex(12)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
    }

    private var hasConnectedSource: Bool {
        appModel.deviceState != nil || appModel.sourceIsOnline
    }

    private var orderedEntriesForDisplay: [RegistryEntry] {
        let modulesByID = Dictionary(uniqueKeysWithValues: appModel.orderedModules.map { ($0.id, $0) })
        let ids = displayedModuleIDs.isEmpty ? appModel.orderedModules.map(\.id) : displayedModuleIDs
        return ids.compactMap { modulesByID[$0] }
    }

    private var availableMetricTokens: [MetricToken] {
        let assignedIDs = assignedMetricTokenIDs
        return allMetricTokens.filter { !assignedIDs.contains($0.id) }
    }

    private var allMetricTokens: [MetricToken] {
        var tokens: [MetricToken] = []
        let descriptors = appModel.availableCPUCoreDescriptors
        if descriptors.contains(where: { $0.kind == .performance }) {
            tokens.append(MetricToken(kind: .allPerformance))
        }
        if descriptors.contains(where: { $0.kind == .efficiency }) {
            tokens.append(MetricToken(kind: .allEfficiency))
        }
        tokens.append(contentsOf: descriptors.map { MetricToken(kind: .cpuCore($0.index, $0.kind)) })
        tokens.append(MetricToken(kind: .memory))
        return tokens
    }

    private var assignedMetricTokenIDs: Set<String> {
        var ids = Set<String>()
        for entry in appModel.orderedModules where entry.moduleType == .radiance {
            for channelIndex in 0...1 {
                let binding = appModel.binding(for: entry, channelIndex: channelIndex)
                ids.formUnion(tokenIDs(for: binding.metric))
            }
        }
        return ids
    }

    private var allBalanceTokens: [BalanceMetricToken] {
        [
            BalanceMetricToken(kind: .networkUp),
            BalanceMetricToken(kind: .networkDown),
            BalanceMetricToken(kind: .diskRead),
            BalanceMetricToken(kind: .diskWrite)
        ]
    }

    private var availableBalanceTokens: [BalanceMetricToken] {
        let assignedIDs = Set(appModel.orderedModules.flatMap { entry -> [String] in
            guard entry.moduleType == .balance else { return [] }
            return [0, 1].compactMap { channelIndex in
                let metric = appModel.binding(for: entry, channelIndex: channelIndex).metric
                guard metric.userAssigned else { return nil }
                return BalanceMetricToken.id(for: metric.kind)
            }
        })
        return allBalanceTokens.filter { !assignedIDs.contains($0.id) }
    }

    private func sourceModule(layout: OverviewLayout) -> some View {
        OverviewProductModule(
            imageName: "origin",
            imageSize: layout.sourceFrame.size,
            effectiveWidthPixels: OverviewMetrics.sourceVisibleWidth,
            isDimmed: !appModel.sourceIsOnline,
            hoveredHotspot: $hoveredHotspot,
            activeRadianceTarget: $activeRadianceTarget,
            activeBalanceTarget: $activeBalanceTarget,
            entry: nil,
            assignedBindings: [:],
            candidatePanelFrame: nil,
            balanceCandidatePanelFrame: nil,
            metricTokenNamespace: metricTokenNamespace
        )
        .position(layout.sourceCenter)
    }

    private func moduleView(for entry: RegistryEntry, layout: OverviewLayout) -> some View {
        let center = layout.moduleCenters[entry.id] ?? layout.sourceCenter
        let imageSize = layout.moduleFrames[entry.id]?.size ?? layout.defaultImageSize(for: entry.moduleType)
        let isDragging = draggedModuleID == entry.id
        let baseCenter = isDragging ? (dragStartCenter ?? center) : center
        let targetCenter = CGPoint(
            x: baseCenter.x + (isDragging ? dragTranslation.width : 0),
            y: baseCenter.y + (isDragging ? dragTranslation.height : 0)
        )
        return OverviewProductModule(
            imageName: imageName(for: entry.moduleType),
            imageSize: imageSize,
            effectiveWidthPixels: visibleWidth(for: entry.moduleType),
            isDimmed: !appModel.isEntryOnline(entry),
            hoveredHotspot: $hoveredHotspot,
            activeRadianceTarget: $activeRadianceTarget,
            activeBalanceTarget: $activeBalanceTarget,
            entry: entry,
            assignedBindings: assignedBindings(for: entry),
            candidatePanelFrame: activeRadianceTarget.map { target in
                layout.candidatePanelFrame(
                    for: target,
                    assignedHeight: assignedStackHeight(
                        for: orderedEntriesForDisplay.first(where: { $0.id == target.moduleID }),
                        channelIndex: target.channelIndex
                    )
                )
            },
            balanceCandidatePanelFrame: activeBalanceTarget.map { layout.balanceCandidatePanelFrame(for: $0) },
            metricTokenNamespace: metricTokenNamespace
        )
        .position(targetCenter)
        .zIndex(isDragging ? 11 : 9)
    }

    private func globalInteractionLayer(layout: OverviewLayout) -> some View {
        ZStack(alignment: .topLeading) {
            hotspotRect(
                rect: layout.sourceHotspot,
                cornerRadius: 0,
                isActive: hoveredHotspot == .source
            )
            .onHover { hovering in
                hoveredHotspot = hovering ? .source : nil
            }
            .simultaneousGesture(TapGesture().onEnded {
                withAnimation(.easeOut(duration: 0.24)) {
                    sourceSettingsVisible.toggle()
                    activeRadianceTarget = nil
                    activeBalanceTarget = nil
                    selectedMetricTokenIDs = []
                }
                appModel.selectSource()
            })

            ForEach(layout.radianceDropZones.sorted(by: { $0.key.id < $1.key.id }), id: \.key.id) { target, rect in
                if let entry = orderedEntriesForDisplay.first(where: { $0.id == target.moduleID }) {
                    radianceHotspot(target: target, rect: rect, entry: entry, layout: layout)
                }
            }

            ForEach(layout.balanceHotspots.sorted(by: { $0.key.id < $1.key.id }), id: \.key.id) { target, rect in
                if let entry = orderedEntriesForDisplay.first(where: { $0.id == target.moduleID }) {
                    balanceHotspot(target: target, rect: rect, entry: entry, layout: layout)
                }
            }
        }
        .frame(width: layout.boundsSize.width, height: layout.boundsSize.height, alignment: .topLeading)
        .zIndex(8)
    }

    private func radianceHotspot(
        target: RadianceDropTarget,
        rect: CGRect,
        entry: RegistryEntry,
        layout: OverviewLayout
    ) -> some View {
        hotspotRect(
            rect: rect,
            cornerRadius: 16,
            isActive: hoveredHotspot == .radiance(target) || activeRadianceTarget == target
        )
        .onHover { hovering in
            hoveredHotspot = hovering ? .radiance(target) : nil
        }
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation(.easeOut(duration: 0.22)) {
                activeRadianceTarget = target
                activeBalanceTarget = nil
                sourceSettingsVisible = false
                selectedMetricTokenIDs = []
            }
        })
        .simultaneousGesture(dragGesture(for: entry, layout: layout))
    }

    private func balanceHotspot(
        target: BalanceDropTarget,
        rect: CGRect,
        entry: RegistryEntry,
        layout: OverviewLayout
    ) -> some View {
        hotspotRect(
            rect: rect,
            cornerRadius: 0,
            isActive: hoveredHotspot == .balance(target) || activeBalanceTarget == target
        )
        .onHover { hovering in
            hoveredHotspot = hovering ? .balance(target) : nil
        }
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation(.easeOut(duration: 0.22)) {
                activeBalanceTarget = target
                activeRadianceTarget = nil
                sourceSettingsVisible = false
                selectedMetricTokenIDs = []
            }
        })
        .simultaneousGesture(dragGesture(for: entry, layout: layout))
    }

    private func hotspotRect(rect: CGRect, cornerRadius: CGFloat, isActive: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())

            if isActive {
                if cornerRadius > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.86), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .blur(radius: 0.8)
                        .shadow(color: .white.opacity(0.9), radius: 14)
                        .allowsHitTesting(false)
                } else {
                    Rectangle()
                        .stroke(Color.white.opacity(0.86), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .blur(radius: 0.8)
                        .shadow(color: .white.opacity(0.9), radius: 14)
                        .allowsHitTesting(false)
                }
            }
        }
        .offset(x: rect.minX, y: rect.minY)
    }

    private func dragGesture(for entry: RegistryEntry, layout: OverviewLayout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("overview"))
            .onChanged { value in
                if draggedModuleID != entry.id {
                    draggedModuleID = entry.id
                    dragStartCenter = layout.moduleCenters[entry.id] ?? .zero
                    dragTranslation = .zero
                    selectedMetricTokenIDs = []
                }
                dragTranslation = value.translation
                let draggedCenterX = (dragStartCenter ?? value.startLocation).x + value.translation.width
                updateDisplayOrder(for: entry.id, draggedCenterX: draggedCenterX, layout: layout)
            }
            .onEnded { _ in
                let finalOrder = displayedModuleIDs
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                    draggedModuleID = nil
                    dragStartCenter = nil
                    dragTranslation = .zero
                }
                appModel.reorderModuleIDs(finalOrder)
            }
    }

    private func updateDisplayOrder(for moduleID: Int, draggedCenterX: CGFloat, layout: OverviewLayout) {
        guard var currentIndex = displayedModuleIDs.firstIndex(of: moduleID) else { return }
        let otherIDs = displayedModuleIDs.filter { $0 != moduleID }
        var insertionIndex = otherIDs.count

        for (index, id) in otherIDs.enumerated() {
            guard let center = layout.moduleCenters[id] else { continue }
            if draggedCenterX < center.x {
                insertionIndex = index
                break
            }
        }

        var next = otherIDs
        next.insert(moduleID, at: insertionIndex)
        guard next != displayedModuleIDs else { return }

        currentIndex = displayedModuleIDs.firstIndex(of: moduleID) ?? currentIndex
        let movingRight = insertionIndex > currentIndex
        let response = movingRight ? 0.38 : 0.32
        withAnimation(.interactiveSpring(response: response, dampingFraction: 0.82, blendDuration: 0.1)) {
            displayedModuleIDs = next
        }
    }

    private func overviewLayout(in size: CGSize) -> OverviewLayout {
        let entries = orderedEntriesForDisplay
        let visiblePixels = OverviewMetrics.sourceVisibleWidth
            + entries.reduce(CGFloat.zero) { partial, entry in
                partial + visibleWidth(for: entry.moduleType)
            }
        let horizontalMargin: CGFloat = 48
        let availableWidth = max(size.width - horizontalMargin, 180)
        let widthFit = availableWidth / max(visiblePixels / 1000, 0.1)
        let verticalReserve: CGFloat = 190
        let bottomPadding: CGFloat = 42
        let maxImagePixelHeight = max(
            OverviewMetrics.sourcePixelSize.height,
            entries.map { OverviewMetrics.imagePixelSize(for: $0.moduleType).height }.max() ?? 1000
        )
        let heightFit = max(size.height - verticalReserve - bottomPadding, 160) / max(maxImagePixelHeight / 1000, 1)
        let imageSide = min(420, max(120, min(widthFit, heightFit)))
        let scale = imageSide / 1000
        let stageWidth = size.width
        let totalVisibleWidth = visiblePixels * scale
        var cursorX = max((stageWidth - totalVisibleWidth) / 2, horizontalMargin / 2)
        let commonBottomY = size.height - bottomPadding
        let centerY = commonBottomY - imageSide / 2
        let sourceCenter = CGPoint(
            x: cursorX + OverviewMetrics.sourceVisibleWidth * scale / 2,
            y: centerY
        )
        let sourceFrame = imageFrame(centerX: sourceCenter.x, bottomY: commonBottomY, moduleType: nil, imageSide: imageSide)
        let sourceHotspot = rectInStage(OverviewMetrics.sourceHotspot, imageFrame: sourceFrame)
        cursorX += OverviewMetrics.sourceVisibleWidth * scale

        var centers: [Int: CGPoint] = [:]
        var moduleFrames: [Int: CGRect] = [:]
        for entry in entries {
            let width = visibleWidth(for: entry.moduleType) * scale
            let centerX = cursorX + width / 2
            let frameBottomY = commonBottomY - (entry.moduleType == .balance ? 1 : 0)
            let frame = imageFrame(centerX: centerX, bottomY: frameBottomY, moduleType: entry.moduleType, imageSide: imageSide)
            centers[entry.id] = CGPoint(x: frame.midX, y: frame.midY)
            moduleFrames[entry.id] = frame
            cursorX += width
        }

        var dropZones: [RadianceDropTarget: CGRect] = [:]
        var balanceHotspots: [BalanceDropTarget: CGRect] = [:]
        for entry in entries where entry.moduleType == .radiance {
            guard let frame = moduleFrames[entry.id] else { continue }
            for channel in OverviewMetrics.radianceTubes {
                dropZones[RadianceDropTarget(moduleID: entry.id, channelIndex: channel.channelIndex)] = rectInStage(
                    channel.rect,
                    imageFrame: frame
                )
            }
        }
        for entry in entries where entry.moduleType == .balance {
            guard let frame = moduleFrames[entry.id] else { continue }
            for gauge in OverviewMetrics.balanceGauges {
                balanceHotspots[BalanceDropTarget(moduleID: entry.id, channelIndex: gauge.channelIndex)] = rectInStage(
                    gauge.rect,
                    imageFrame: frame
                )
            }
        }

        let candidatePanelSize = candidatePanelSize(for: availableMetricTokens, imageSide: imageSide, boundsSize: size)
        let candidatePanelColumnCount = candidateColumnCount(for: candidatePanelSize.width)
        return OverviewLayout(
            imageSide: imageSide,
            sourceCenter: sourceCenter,
            sourceFrame: sourceFrame,
            sourceHotspot: sourceHotspot,
            moduleCenters: centers,
            moduleFrames: moduleFrames,
            radianceDropZones: dropZones,
            balanceHotspots: balanceHotspots,
            sourceSettingsY: min(max(sourceHotspot.minY - 76, 76), size.height - 76),
            sourceSettingsWidth: min(imageSide * OverviewMetrics.sourceVisibleWidth / 1000, max(size.width - 72, 120)),
            candidatePanelSize: candidatePanelSize,
            candidatePanelColumnCount: candidatePanelColumnCount,
            boundsSize: size
        )
    }

    private func candidatePanelSize(for tokens: [MetricToken], imageSide: CGFloat, boundsSize: CGSize) -> CGSize {
        let maxBodyWidth = imageSide * OverviewMetrics.moduleVisibleWidth / 1000
        let maxWidth = min(maxBodyWidth, max(boundsSize.width - 48, 120))
        let width = min(max(maxWidth, 320), max(boundsSize.width - 48, 120))
        let columns = candidateColumnCount(for: width)
        let groups = candidatePanelGroupCount(for: tokens)
        let averageRows = tokens.contains { $0.kind == .allPerformance || $0.kind == .allEfficiency } ? 1 : 0
        let cpuCount = tokens.filter {
            if case .cpuCore = $0.kind { return true }
            return false
        }.count
        let cpuRows = cpuCount == 0 ? 0 : Int(ceil(Double(cpuCount) / Double(columns)))
        let otherRows = tokens.contains { $0.kind == .memory } ? 1 : 0
        let rowCount = averageRows + cpuRows + otherRows
        let spacing = max(groups - 1, 0) * 10
        let height = CGFloat(rowCount * 30 + spacing + 24)
        return CGSize(width: width, height: max(54, height))
    }

    private func candidatePanelGroupCount(for tokens: [MetricToken]) -> Int {
        var count = 0
        if tokens.contains(where: { $0.kind == .allPerformance || $0.kind == .allEfficiency }) {
            count += 1
        }
        if tokens.contains(where: {
            if case .cpuCore = $0.kind { return true }
            return false
        }) {
            count += 1
        }
        if tokens.contains(where: { $0.kind == .memory }) {
            count += 1
        }
        return count
    }

    private func candidateColumnCount(for width: CGFloat) -> Int {
        let available = max(width - 24, 58)
        let count = Int(floor((available + 8) / 66))
        return min(max(count, 1), 4)
    }

    private func rectInStage(_ rect: CGRect, center: CGPoint, imageSide: CGFloat) -> CGRect {
        rectInStage(rect, imageFrame: CGRect(x: center.x - imageSide / 2, y: center.y - imageSide / 2, width: imageSide, height: imageSide))
    }

    private func rectInStage(_ rect: CGRect, imageFrame: CGRect) -> CGRect {
        let scale = imageFrame.width / 1000
        return CGRect(
            x: imageFrame.minX + rect.minX * scale,
            y: imageFrame.minY + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func imageFrame(centerX: CGFloat, bottomY: CGFloat, moduleType: ModuleType?, imageSide: CGFloat) -> CGRect {
        let pixelSize: CGSize
        if let moduleType {
            pixelSize = OverviewMetrics.imagePixelSize(for: moduleType)
        } else {
            pixelSize = OverviewMetrics.sourcePixelSize
        }
        let width = imageSide
        let height = imageSide * pixelSize.height / pixelSize.width
        return CGRect(x: centerX - width / 2, y: bottomY - height, width: width, height: height)
    }

    private func assignMetricTokens(_ tokenIDs: Set<String>, to target: RadianceDropTarget) {
        guard
            let entry = appModel.orderedModules.first(where: { $0.id == target.moduleID }),
            entry.moduleType == .radiance
        else {
            return
        }

        let tokens = allMetricTokens.filter { tokenIDs.contains($0.id) }
        guard !tokens.isEmpty else { return }

        if tokens.contains(where: { $0.kind == .memory }) {
            appModel.assignMemoryUsage(for: entry, channelIndex: target.channelIndex)
            selectedMetricTokenIDs = []
            return
        }

        var coreIndices = Set<Int>()
        for token in tokens {
            switch token.kind {
            case .allEfficiency:
                coreIndices.formUnion(appModel.cpuCoreIndices(kind: .efficiency))
            case .allPerformance:
                coreIndices.formUnion(appModel.cpuCoreIndices(kind: .performance))
            case .cpuCore(let index, _):
                coreIndices.insert(index)
            case .memory:
                break
            }
        }

        if !coreIndices.isEmpty {
            let current = appModel.binding(for: entry, channelIndex: target.channelIndex).metric
            if current.kind == .cpuCore || current.kind == .cpuCoreAverage {
                coreIndices.formUnion(current.coreIndices)
            }
            appModel.assignCPUCores(Array(coreIndices).sorted(), for: entry, channelIndex: target.channelIndex)
        }
        selectedMetricTokenIDs = []
    }

    private func assignBalanceMetricToken(_ tokenID: String, to target: BalanceDropTarget) {
        guard
            let entry = appModel.orderedModules.first(where: { $0.id == target.moduleID }),
            entry.moduleType == .balance,
            let token = allBalanceTokens.first(where: { $0.id == tokenID })
        else {
            return
        }
        appModel.assignMetricKind(token.metricKind, for: entry, channelIndex: target.channelIndex)
    }

    private func tokenIDs(for metric: MetricBinding) -> Set<String> {
        switch metric.kind {
        case .memoryUsage:
            return ["memory"]
        case .cpuCore, .cpuCoreAverage:
            let coreSet = Set(metric.coreIndices)
            let efficiencySet = Set(appModel.cpuCoreIndices(kind: .efficiency))
            let performanceSet = Set(appModel.cpuCoreIndices(kind: .performance))
            if !efficiencySet.isEmpty && coreSet == efficiencySet {
                return ["all-efficiency"]
            }
            if !performanceSet.isEmpty && coreSet == performanceSet {
                return ["all-performance"]
            }
            return Set(metric.coreIndices.map { "cpu-\($0)" })
        default:
            return []
        }
    }

    private func imageName(for moduleType: ModuleType) -> String {
        switch moduleType {
        case .radiance:
            return "radiance"
        case .balance:
            return "balance"
        case .unknown:
            return "balance"
        }
    }

    private func visibleWidth(for moduleType: ModuleType) -> CGFloat {
        switch moduleType {
        case .radiance, .balance, .unknown:
            return OverviewMetrics.moduleVisibleWidth
        }
    }

    private func assignedBindings(for entry: RegistryEntry) -> [Int: ChannelBinding] {
        switch entry.moduleType {
        case .radiance:
            return [
                0: appModel.binding(for: entry, channelIndex: 0),
                1: appModel.binding(for: entry, channelIndex: 1)
            ]
        case .balance:
            return [
                0: appModel.binding(for: entry, channelIndex: 0),
                1: appModel.binding(for: entry, channelIndex: 1)
            ]
        case .unknown:
            return [:]
        }
    }

    private func assignedStackHeight(for entry: RegistryEntry?, channelIndex: Int) -> CGFloat {
        guard let entry else { return 0 }
        return assignedStackHeight(for: appModel.binding(for: entry, channelIndex: channelIndex))
    }

    private func assignedStackHeight(for binding: ChannelBinding?) -> CGFloat {
        guard let binding else { return 0 }
        let chipCount: Int
        switch binding.metric.kind {
        case .cpuCore, .cpuCoreAverage:
            let coreSet = Set(binding.metric.coreIndices)
            let efficiencySet = Set(appModel.cpuCoreIndices(kind: .efficiency))
            let performanceSet = Set(appModel.cpuCoreIndices(kind: .performance))
            if (!efficiencySet.isEmpty && coreSet == efficiencySet) || (!performanceSet.isEmpty && coreSet == performanceSet) {
                chipCount = 1
            } else {
                chipCount = max(binding.metric.coreIndices.count, 1)
            }
        case .memoryUsage:
            chipCount = 1
        default:
            chipCount = 0
        }
        return CGFloat(chipCount) * 24 + CGFloat(max(chipCount - 1, 0)) * 5
    }
}

private struct OverviewProductModule: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var displayedPercents: [Int: Double] = [:]
    @State private var displayedVelocities: [Int: Double] = [:]
    let imageName: String
    let imageSize: CGSize
    let effectiveWidthPixels: CGFloat
    let isDimmed: Bool
    @Binding var hoveredHotspot: OverviewHotspot?
    @Binding var activeRadianceTarget: RadianceDropTarget?
    @Binding var activeBalanceTarget: BalanceDropTarget?
    let entry: RegistryEntry?
    let assignedBindings: [Int: ChannelBinding]
    let candidatePanelFrame: CGRect?
    let balanceCandidatePanelFrame: CGRect?
    let metricTokenNamespace: Namespace.ID

    var body: some View {
        ZStack {
            ProductPNGImage(name: imageName)
                .frame(width: imageSize.width, height: imageSize.height)
                .opacity(isDimmed ? 0.52 : 1)
                .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 18)
                .allowsHitTesting(false)

            if let entry, entry.moduleType == .radiance {
                radianceSimulatorOverlays(entry: entry)
            }

            if let entry, entry.moduleType == .radiance {
                radianceAssignedStacks(entry: entry)
            }

            if let entry, entry.moduleType == .balance {
                balanceOverlays(entry: entry)
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)
        .task(id: entry?.id) {
            guard entry != nil else { return }
            await runSimulatorLoop()
        }
    }

    private var moduleChannelIndices: [Int] {
        guard let entry else { return [] }
        switch entry.moduleType {
        case .radiance:
            return OverviewMetrics.radianceTubes.map(\.channelIndex)
        case .balance:
            return OverviewMetrics.balanceGauges.map(\.channelIndex)
        case .unknown:
            return []
        }
    }

    private func currentDisplayedPercent(for channelIndex: Int) -> Double {
        displayedPercents[channelIndex] ?? 0
    }

    private func targetPercent(for entry: RegistryEntry, channelIndex: Int) -> Double {
        appModel.simulatedOutputPercent(for: entry, channelIndex: channelIndex)
    }

    private func isCalibrationHighlightActive(for entry: RegistryEntry, channelIndex: Int) -> Bool {
        appModel.isCalibratingChannel(for: entry, channelIndex: channelIndex)
    }

    private func isEntryOnline(_ entry: RegistryEntry) -> Bool {
        appModel.isEntryOnline(entry)
    }

    private func radianceSimulatorOverlays(entry: RegistryEntry) -> some View {
        ZStack {
            ForEach(OverviewMetrics.radianceBars) { bar in
                let percent = currentDisplayedPercent(for: bar.channelIndex)
                RadianceBarShape(bar: bar, percent: percent)
                    .fill(OverviewMetrics.simulatorGlow)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .shadow(color: OverviewMetrics.simulatorGlow.opacity(0.66), radius: 12)
                    .shadow(color: OverviewMetrics.simulatorGlow.opacity(0.32), radius: 24)
                    .opacity(isDimmed ? 0.48 : 0.94)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }

            ForEach(OverviewMetrics.radianceTubes) { tube in
                if isCalibrationHighlightActive(for: entry, channelIndex: tube.channelIndex) {
                    let rect = scaledRect(tube.rect)
                    CalibrationFocusOverlay(
                        rect: rect,
                        cornerRadius: 18,
                        label: "目标 \(Int((targetPercent(for: entry, channelIndex: tube.channelIndex) * 100).rounded()))%"
                    )
                    .zIndex(5)
                }
            }
        }
    }

    private func radianceAssignedStacks(entry: RegistryEntry) -> some View {
        ZStack {
            ForEach(OverviewMetrics.radianceTubes) { tube in
                let target = RadianceDropTarget(moduleID: entry.id, channelIndex: tube.channelIndex)
                let rect = scaledRect(tube.rect)
                let binding = assignedBindings[tube.channelIndex]
                let stackHeight = assignedStackHeight(for: binding)
                let stackBottomY = rect.minY - 14
                AssignedMetricStack(
                    entry: entry,
                    channelIndex: tube.channelIndex,
                    binding: binding,
                    candidatePanelFrame: candidatePanelFrame,
                    metricTokenNamespace: metricTokenNamespace
                )
                    .position(x: rect.midX, y: stackBottomY - stackHeight / 2)
                    .opacity(activeRadianceTarget == nil || activeRadianceTarget == target ? 1 : 0.58)
                    .zIndex(20)

            }
        }
    }

    private func assignedStackHeight(for binding: ChannelBinding?) -> CGFloat {
        let chipCount: Int
        guard let binding else { return 0 }
        switch binding.metric.kind {
        case .cpuCore, .cpuCoreAverage:
            let coreSet = Set(binding.metric.coreIndices)
            let efficiencySet = Set(appModel.cpuCoreIndices(kind: .efficiency))
            let performanceSet = Set(appModel.cpuCoreIndices(kind: .performance))
            if (!efficiencySet.isEmpty && coreSet == efficiencySet) || (!performanceSet.isEmpty && coreSet == performanceSet) {
                chipCount = 1
            } else {
                chipCount = max(binding.metric.coreIndices.count, 1)
            }
        case .memoryUsage:
            chipCount = 1
        default:
            chipCount = 1
        }
        return CGFloat(chipCount) * 24 + CGFloat(max(chipCount - 1, 0)) * 5
    }

    private func scaledRect(_ rect: CGRect) -> CGRect {
        let scale = imageSize.width / 1000
        return CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func scaledPoint(_ point: CGPoint) -> CGPoint {
        let scale = imageSize.width / 1000
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private func balanceOverlays(entry: RegistryEntry) -> some View {
        ZStack {
            ForEach(OverviewMetrics.balanceGauges) { gauge in
                let target = BalanceDropTarget(moduleID: entry.id, channelIndex: gauge.channelIndex)
                let rect = scaledRect(gauge.rect)

                if let binding = assignedBindings[gauge.channelIndex],
                   let svgMarkup = binding.metric.dialSVGMarkup {
                    ZStack {
                        Rectangle()
                            .fill(Color(white: 183.0 / 255.0))
                        ImportedGaugeSVG(markup: svgMarkup)
                            .padding(1)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(isDimmed ? 0.52 : 1)
                    .allowsHitTesting(false)
                    .zIndex(3)
                }

                if let needle = OverviewMetrics.balanceNeedles.first(where: { $0.channelIndex == gauge.channelIndex }) {
                    BalanceNeedleShape(
                        center: scaledPoint(needle.center),
                        length: needle.length * (imageSize.width / 1000),
                        percent: currentDisplayedPercent(for: gauge.channelIndex)
                    )
                    .stroke(
                        Color(red: 0.93, green: 0.18, blue: 0.18),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                    .shadow(color: Color.red.opacity(0.38), radius: 5)
                    .opacity(isDimmed ? 0.5 : 0.96)
                    .mask(
                        Rectangle()
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    )
                    .allowsHitTesting(false)
                    .zIndex(4)
                }

                if isCalibrationHighlightActive(for: entry, channelIndex: gauge.channelIndex) {
                    CalibrationFocusOverlay(
                        rect: rect,
                        cornerRadius: 0,
                        label: "目标 \(Int((targetPercent(for: entry, channelIndex: gauge.channelIndex) * 100).rounded()))%"
                    )
                    .zIndex(5)
                }

                if let binding = assignedBindings[gauge.channelIndex],
                   binding.metric.kind != .none,
                   binding.metric.userAssigned {
                    BalanceAssignedMetricLabel(
                        entry: entry,
                        channelIndex: gauge.channelIndex,
                        binding: binding,
                        candidatePanelFrame: balanceCandidatePanelFrame,
                        metricTokenNamespace: metricTokenNamespace
                    )
                        .environmentObject(appModel)
                        .position(x: rect.midX, y: rect.minY - 32)
                        .opacity(activeBalanceTarget == nil || activeBalanceTarget == target ? 1 : 0.62)
                        .zIndex(20)
                }
            }
        }
    }

    private func runSimulatorLoop() async {
        var lastTimestamp = CACurrentMediaTime()
        while !Task.isCancelled {
            let now = CACurrentMediaTime()
            let deltaTime = min(max(now - lastTimestamp, 1.0 / 120.0), 0.05)
            lastTimestamp = now

            if let entry {
                let config = appModel.smoothingConfig(for: entry.moduleType)
                let online = isEntryOnline(entry)
                for channelIndex in moduleChannelIndices {
                    let target = targetPercent(for: entry, channelIndex: channelIndex)
                    let highlighted = isCalibrationHighlightActive(for: entry, channelIndex: channelIndex)
                    let current = displayedPercents[channelIndex] ?? target
                    let velocity = displayedVelocities[channelIndex] ?? 0
                    let nextState = nextSimulatorState(
                        current: current,
                        velocity: velocity,
                        target: target,
                        config: config,
                        deltaTime: deltaTime,
                        immediate: highlighted || !online
                    )
                    displayedPercents[channelIndex] = nextState.percent
                    displayedVelocities[channelIndex] = nextState.velocity
                }
            }

            try? await Task.sleep(nanoseconds: 16_666_667)
        }
    }

    private func nextSimulatorState(
        current: Double,
        velocity: Double,
        target: Double,
        config: SmoothingConfig,
        deltaTime: Double,
        immediate: Bool
    ) -> (percent: Double, velocity: Double) {
        let clampedTarget = min(max(target, 0), 1)
        if immediate {
            return (clampedTarget, 0)
        }

        let settleSeconds = max(Double(config.settleTimeMs) / 1000.0, 0.12)
        let maxVelocity = max(config.vMax / 5.0, 0.18)
        let maxAcceleration = max(config.aMax / 7.5, 0.22)
        let delta = clampedTarget - current

        if abs(delta) < 0.0008 && abs(velocity) < 0.002 {
            return (clampedTarget, 0)
        }

        let desiredVelocity = min(max(delta / settleSeconds, -maxVelocity), maxVelocity)
        let velocityDelta = desiredVelocity - velocity
        let clampedVelocityDelta = min(max(velocityDelta, -maxAcceleration * deltaTime), maxAcceleration * deltaTime)
        let nextVelocity = velocity + clampedVelocityDelta
        let nextPercent = min(max(current + nextVelocity * deltaTime, 0), 1)
        return (nextPercent, nextVelocity)
    }
}

private struct BalanceAssignedMetricLabel: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: RegistryEntry
    let channelIndex: Int
    let binding: ChannelBinding
    let candidatePanelFrame: CGRect?
    let metricTokenNamespace: Namespace.ID
    @State private var dragOffset: CGSize = .zero

    private var token: BalanceMetricToken {
        BalanceMetricToken(kind: binding.metric.kind)
    }

    var body: some View {
        Text(token.label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(token.color.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(token.color.opacity(0.64), lineWidth: 1)
            )
            .shadow(color: token.color.opacity(0.18), radius: 7, y: 3)
            .matchedGeometryEffect(id: "balance-\(token.id)", in: metricTokenNamespace)
            .offset(dragOffset)
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture)
            .onRightClick {
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
                    appModel.removeAssignedBalanceMetricToken(token.id, for: entry, channelIndex: channelIndex)
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("overview"))
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if let candidatePanelFrame, candidatePanelFrame.contains(value.location) {
                    withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
                        appModel.removeAssignedBalanceMetricToken(token.id, for: entry, channelIndex: channelIndex)
                    }
                }
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
                    dragOffset = .zero
                }
            }
    }
}

private struct RadianceBarShape: Shape {
    let bar: RadianceSimulatorBar
    var percent: Double

    var animatableData: Double {
        get { percent }
        set { percent = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 1000
        let baseFrame = bar.rect(for: percent)
        let frame = CGRect(
            x: baseFrame.minX * scale,
            y: baseFrame.minY * scale,
            width: baseFrame.width * scale,
            height: baseFrame.height * scale
        )
        return Path(frame)
    }
}

private struct BalanceNeedleShape: Shape {
    let center: CGPoint
    let length: CGFloat
    var percent: Double

    var animatableData: Double {
        get { percent }
        set { percent = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedPercent = min(max(percent, 0), 1)
        let angle = Angle.degrees(135 - 90 * clampedPercent)
        let radians = angle.radians
        let endpoint = CGPoint(
            x: center.x + CGFloat(Darwin.cos(radians)) * length,
            y: center.y - CGFloat(Darwin.sin(radians)) * length
        )
        var path = Path()
        path.move(to: center)
        path.addLine(to: endpoint)
        return path
    }
}

private struct CalibrationFocusOverlay: View {
    let rect: CGRect
    let cornerRadius: CGFloat
    let label: String

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.92), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.12))
                )
                .shadow(color: Color.white.opacity(0.55), radius: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .position(x: rect.midX, y: max(rect.minY - 18, 14))
        }
    }
}

private struct ImportedGaugeSVG: View {
    let markup: String

    var body: some View {
        GaugeSVGWebView(markup: markup)
    }
}

private struct GaugeSVGWebView: NSViewRepresentable {
    let markup: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html(for: markup), baseURL: nil)
    }

    private func html(for svg: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        html, body {
          margin: 0;
          padding: 0;
          width: 100%;
          height: 100%;
          overflow: hidden;
          background: transparent;
        }
        svg {
          display: block;
          width: 100%;
          height: 100%;
        }
        svg *[stroke]:not([stroke="none"]) {
          stroke: #000 !important;
        }
        svg *[fill]:not([fill="none"]) {
          fill: #000 !important;
        }
        </style>
        </head>
        <body>\(svg)</body>
        </html>
        """
    }
}

private struct TubeActionButtons: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: RegistryEntry
    let channelIndex: Int
    var importAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) ? "寻找中" : "寻找") {
                appModel.locateChannel(for: entry, channelIndex: channelIndex)
            }
            .disabled(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) || appModel.isStartingCalibration(for: entry, channelIndex: channelIndex))

            Button(appModel.isStartingCalibration(for: entry, channelIndex: channelIndex) ? "准备中" : "校准") {
                appModel.beginCalibration(for: entry, channelIndex: channelIndex)
            }
            .disabled(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) || appModel.isStartingCalibration(for: entry, channelIndex: channelIndex))

            if let importAction {
                Button("导入设置") {
                    importAction()
                }
                .disabled(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) || appModel.isStartingCalibration(for: entry, channelIndex: channelIndex))
            }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(Color.white.opacity(0.22))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SourceInlineSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var refreshInterval: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("IP地址")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(appModel.deviceState?.ip ?? "--")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("采样频率")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(clampedRefreshInterval, specifier: "%.1f") 秒")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                Slider(
                    value: Binding(
                        get: { clampedRefreshInterval },
                        set: { refreshInterval = $0 }
                    ),
                    in: 0...2.0,
                    step: 0.1
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var clampedRefreshInterval: Double {
        min(max(refreshInterval, 0), 2.0)
    }
}

private struct MetricCandidatePanel: View {
    let tokens: [MetricToken]
    @Binding var selectedTokenIDs: Set<String>
    let dropZones: [RadianceDropTarget: CGRect]
    let columnCount: Int
    let activeTarget: RadianceDropTarget
    let assignTokens: (Set<String>, RadianceDropTarget) -> Void
    let metricTokenNamespace: Namespace.ID

    @State private var draggingTokenIDs: Set<String> = []
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                if !averageTokens.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(averageTokens) { token in
                            draggableToken(token)
                        }
                    }
                }

                if !cpuTokens.isEmpty {
                    LazyVGrid(columns: cpuColumns, alignment: .leading, spacing: 8) {
                        ForEach(cpuTokens) { token in
                            draggableToken(token)
                        }
                    }
                }

                let otherTokens = [memoryToken].compactMap { $0 }
                if !otherTokens.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(otherTokens) { token in
                            draggableToken(token)
                        }
                        Spacer(minLength: 0)
                    }
                }

            }
            .padding(12)
        }
        .onChange(of: tokens.map(\.id)) { _, ids in
            selectedTokenIDs = selectedTokenIDs.intersection(Set(ids))
        }
    }

    private var averageTokens: [MetricToken] {
        tokens.filter { $0.kind == .allPerformance || $0.kind == .allEfficiency }
    }

    private var cpuTokens: [MetricToken] {
        tokens.filter {
            if case .cpuCore = $0.kind {
                return true
            }
            return false
        }
    }

    private var memoryToken: MetricToken? {
        tokens.first { $0.kind == .memory }
    }

    private var cpuColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(58), spacing: 8), count: columnCount)
    }

    private func draggableToken(_ token: MetricToken) -> some View {
        MetricTokenButton(
            token: token,
            isSelected: selectedTokenIDs.contains(token.id)
        )
        .matchedGeometryEffect(id: "metric-\(token.id)", in: metricTokenNamespace)
        .offset(draggingTokenIDs.contains(token.id) ? dragOffset : .zero)
        .zIndex(draggingTokenIDs.contains(token.id) ? 4 : 1)
        .highPriorityGesture(tokenDragGesture(for: token))
        .onTapGesture {
            let ids = NSEvent.modifierFlags.contains(.shift) && !selectedTokenIDs.isEmpty
                ? selectedTokenIDs.union([token.id])
                : [token.id]
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82)) {
                assignTokens(ids, activeTarget)
            }
        }
    }

    private func updateSelection(for token: MetricToken) {
        if NSEvent.modifierFlags.contains(.shift) {
            if selectedTokenIDs.contains(token.id) {
                selectedTokenIDs.remove(token.id)
            } else {
                selectedTokenIDs.insert(token.id)
            }
        } else {
            selectedTokenIDs = [token.id]
        }
    }

    private func tokenDragGesture(for token: MetricToken) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("overview"))
            .onChanged { value in
                if draggingTokenIDs.isEmpty {
                    if !selectedTokenIDs.contains(token.id) {
                        selectedTokenIDs = [token.id]
                    }
                    draggingTokenIDs = selectedTokenIDs.isEmpty ? [token.id] : selectedTokenIDs
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                let droppedIDs = draggingTokenIDs.isEmpty ? [token.id] : draggingTokenIDs
                if let target = dropZones.first(where: { _, rect in rect.contains(value.location) })?.key {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82)) {
                        assignTokens(droppedIDs, target)
                    }
                }

                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82)) {
                    dragOffset = .zero
                    draggingTokenIDs = []
                    selectedTokenIDs = []
                }
            }
    }
}

private struct BalanceCandidatePanel: View {
    let tokens: [BalanceMetricToken]
    let dropZones: [BalanceDropTarget: CGRect]
    let activeTarget: BalanceDropTarget
    let assignToken: (String, BalanceDropTarget) -> Void
    let metricTokenNamespace: Namespace.ID

    @State private var draggingTokenID: String?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(tokens) { token in
                        Text(token.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(token.color.opacity(0.16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(token.color.opacity(0.55), lineWidth: 1)
                            )
                            .shadow(color: token.color.opacity(0.16), radius: 7, y: 3)
                            .matchedGeometryEffect(id: "balance-\(token.id)", in: metricTokenNamespace)
                            .offset(draggingTokenID == token.id ? dragOffset : .zero)
                            .zIndex(draggingTokenID == token.id ? 4 : 1)
                            .contentShape(Rectangle())
                            .highPriorityGesture(tokenDragGesture(for: token))
                            .onTapGesture {
                                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82)) {
                                    assignToken(token.id, activeTarget)
                                }
                            }
                    }
                }
            }
            .padding(12)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)]
    }

    private func tokenDragGesture(for token: BalanceMetricToken) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("overview"))
            .onChanged { value in
                draggingTokenID = token.id
                dragOffset = value.translation
            }
            .onEnded { value in
                if let target = dropZones.first(where: { _, rect in rect.contains(value.location) })?.key {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82)) {
                        assignToken(token.id, target)
                    }
                }

                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.82)) {
                    dragOffset = .zero
                    draggingTokenID = nil
                }
            }
    }
}

private struct MetricTokenButton: View {
    let token: MetricToken
    let isSelected: Bool

    var body: some View {
        Text(token.label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .frame(width: token.width, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(token.color.opacity(isSelected ? 0.28 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? token.color.opacity(0.95) : Color.white.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
            )
            .foregroundStyle(.primary)
            .shadow(color: isSelected ? token.color.opacity(0.34) : Color.black.opacity(0.12), radius: isSelected ? 10 : 4, y: 3)
    }
}

private struct AssignedMetricStack: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: RegistryEntry
    let channelIndex: Int
    let binding: ChannelBinding?
    let candidatePanelFrame: CGRect?
    let metricTokenNamespace: Namespace.ID
    @State private var draggingChipID: String?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                Text(chip.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .padding(.horizontal, 8)
                    .frame(width: chip.width, height: 24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(chip.color.opacity(0.72), lineWidth: 1)
                    )
                    .shadow(color: chip.color.opacity(0.22), radius: 8)
                    .matchedGeometryEffect(id: "metric-\(chip.id)", in: metricTokenNamespace)
                    .offset(draggingChipID == chip.id ? dragOffset : .zero)
                    .zIndex(Double(chips.count - index))
                    .contentShape(Rectangle())
                    .highPriorityGesture(chipDragGesture(chip))
                    .onRightClick {
                        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
                            appModel.removeAssignedMetricToken(chip.id, for: entry, channelIndex: channelIndex)
                        }
                    }
            }
        }
    }

    private func chipDragGesture(_ chip: AssignedMetricChip) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("overview"))
            .onChanged { value in
                draggingChipID = chip.id
                dragOffset = value.translation
            }
            .onEnded { value in
                if let candidatePanelFrame, candidatePanelFrame.contains(value.location) {
                    withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
                        appModel.removeAssignedMetricToken(chip.id, for: entry, channelIndex: channelIndex)
                    }
                }

                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
                    draggingChipID = nil
                    dragOffset = .zero
                }
            }
    }

    private var chips: [AssignedMetricChip] {
        guard let binding else { return [] }
        switch binding.metric.kind {
        case .memoryUsage:
            return [
                AssignedMetricChip(
                    id: "memory",
                    label: "内存占用",
                    color: Color(red: 0.25, green: 0.62, blue: 0.95),
                    width: 72
                )
            ]
        case .cpuCoreAverage, .cpuCore:
            let indices = binding.metric.coreIndices.sorted()
            let indexSet = Set(indices)
            let efficiencySet = Set(appModel.cpuCoreIndices(kind: .efficiency))
            let performanceSet = Set(appModel.cpuCoreIndices(kind: .performance))
            if !efficiencySet.isEmpty && indexSet == efficiencySet {
                return [
                    AssignedMetricChip(
                        id: "all-efficiency",
                        label: "小核平均",
                        color: MetricToken.color(for: .efficiency),
                        width: 70
                    )
                ]
            }
            if !performanceSet.isEmpty && indexSet == performanceSet {
                return [
                    AssignedMetricChip(
                        id: "all-performance",
                        label: "大核平均",
                        color: MetricToken.color(for: .performance),
                        width: 70
                    )
                ]
            }
            return indices.map {
                AssignedMetricChip(
                    id: "cpu-\($0)",
                    label: "CPU\($0)",
                    color: MetricToken.color(for: appModel.cpuCoreKind(for: $0)),
                    width: 54
                )
            }
        default:
            return [
                AssignedMetricChip(
                    id: binding.metric.label,
                    label: binding.metric.label,
                    color: MetricToken.color(for: .unknown),
                    width: 76
                )
            ]
        }
    }
}

private struct AssignedMetricChip: Identifiable {
    let id: String
    let label: String
    let color: Color
    let width: CGFloat
}

private struct DeveloperSettingsOverlay: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    appModel.selectSource()
                }

            ScrollView {
                developerContent
                    .padding(22)
            }
            .frame(width: 760)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)

            Button {
                appModel.selectSource()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    @ViewBuilder
    private var developerContent: some View {
        MaintenancePanelView(
            discoveredServices: appModel.discoveredServices,
            deviceState: appModel.deviceState
        )
    }
}

private struct ProductPNGImage: View {
    let name: String

    var body: some View {
        if let image = productImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.18))
        }
    }

    private var productImage: NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "resources") {
            return NSImage(contentsOf: url)
        }
        return Bundle.main.image(forResource: name)
    }
}

private extension View {
    func onRightClick(_ action: @escaping () -> Void) -> some View {
        overlay(RightClickActionView(action: action).allowsHitTesting(true))
    }
}

private struct RightClickActionView: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = RightClickPassthroughNSView(frame: .zero)
        let recognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        recognizer.buttonMask = 0x2
        recognizer.numberOfClicksRequired = 1
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handleClick(_ sender: NSClickGestureRecognizer) {
            guard sender.state == .ended else { return }
            action()
        }
    }

    final class RightClickPassthroughNSView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
                return self
            default:
                return nil
            }
        }
    }
}

private struct OverviewLayout: Equatable {
    let imageSide: CGFloat
    let sourceCenter: CGPoint
    let sourceFrame: CGRect
    let sourceHotspot: CGRect
    let moduleCenters: [Int: CGPoint]
    let moduleFrames: [Int: CGRect]
    let radianceDropZones: [RadianceDropTarget: CGRect]
    let balanceHotspots: [BalanceDropTarget: CGRect]
    let sourceSettingsY: CGFloat
    let sourceSettingsWidth: CGFloat
    let candidatePanelSize: CGSize
    let candidatePanelColumnCount: Int
    let boundsSize: CGSize

    var balanceCandidatePanelSize: CGSize {
        CGSize(width: min(max(boundsSize.width - 48, 160), 196), height: 84)
    }

    func defaultImageSize(for moduleType: ModuleType) -> CGSize {
        let pixelSize = OverviewMetrics.imagePixelSize(for: moduleType)
        return CGSize(width: imageSide, height: imageSide * pixelSize.height / pixelSize.width)
    }

    func candidatePanelCenter(for target: RadianceDropTarget, assignedHeight: CGFloat) -> CGPoint {
        guard let rect = radianceDropZones[target] else {
            return CGPoint(x: boundsSize.width / 2, y: boundsSize.height - candidatePanelSize.height / 2 - 28)
        }
        let actionCenter = radianceActionBarCenter(for: target, assignedHeight: assignedHeight)
        return clampedCenter(
            x: rect.midX,
            y: actionCenter.y - 30 - candidatePanelSize.height / 2,
            size: candidatePanelSize
        )
    }

    func candidatePanelFrame(for target: RadianceDropTarget, assignedHeight: CGFloat) -> CGRect {
        let center = candidatePanelCenter(for: target, assignedHeight: assignedHeight)
        return CGRect(
            x: center.x - candidatePanelSize.width / 2,
            y: center.y - candidatePanelSize.height / 2,
            width: candidatePanelSize.width,
            height: candidatePanelSize.height
        )
    }

    func balanceCandidatePanelCenter(for target: BalanceDropTarget) -> CGPoint {
        let moduleChannelOne = BalanceDropTarget(moduleID: target.moduleID, channelIndex: 0)
        guard let rect = balanceHotspots[moduleChannelOne] ?? balanceHotspots[target] else {
            return CGPoint(x: boundsSize.width / 2, y: boundsSize.height - balanceCandidatePanelSize.height / 2 - 28)
        }
        return clampedCenter(
            x: rect.midX,
            y: rect.minY - 66 - balanceCandidatePanelSize.height / 2,
            size: balanceCandidatePanelSize
        )
    }

    func balanceCandidatePanelFrame(for target: BalanceDropTarget) -> CGRect {
        let center = balanceCandidatePanelCenter(for: target)
        return CGRect(
            x: center.x - balanceCandidatePanelSize.width / 2,
            y: center.y - balanceCandidatePanelSize.height / 2,
            width: balanceCandidatePanelSize.width,
            height: balanceCandidatePanelSize.height
        )
    }

    var dropZoneSignature: String {
        radianceDropZones
            .sorted { $0.key.id < $1.key.id }
            .map { "\($0.key.id):\(Int($0.value.minX)):\(Int($0.value.minY)):\(Int($0.value.width))" }
            .joined(separator: "|")
    }

    func radianceActionBarCenter(for target: RadianceDropTarget, assignedHeight: CGFloat) -> CGPoint {
        guard let rect = radianceDropZones[target] else {
            return CGPoint(x: boundsSize.width / 2, y: 80)
        }
        return clampedCenter(
            x: rect.midX,
            y: rect.minY - assignedHeight - 46,
            size: CGSize(width: 150, height: 30)
        )
    }

    func balanceActionBarCenter(for target: BalanceDropTarget) -> CGPoint {
        guard let rect = balanceHotspots[target] else {
            return CGPoint(x: boundsSize.width / 2, y: boundsSize.height - 80)
        }
        return clampedCenter(
            x: rect.midX,
            y: rect.maxY + 36,
            size: CGSize(width: 210, height: 30)
        )
    }

    private func clampedCenter(x: CGFloat, y: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(x, size.width / 2 + 8), boundsSize.width - size.width / 2 - 8),
            y: min(max(y, size.height / 2 + 8), boundsSize.height - size.height / 2 - 8)
        )
    }
}

private enum OverviewMetrics {
    static let sourceVisibleWidth: CGFloat = 880
    static let moduleVisibleWidth: CGFloat = 664
    static let sourcePixelSize = CGSize(width: 1000, height: 1000)
    static let sourceHotspot = CGRect(x: 60, y: 634, width: 882, height: 328)
    static let simulatorGlow = Color(red: 44 / 255, green: 204 / 255, blue: 113 / 255)
    static let radianceTubes = [
        RadianceTube(channelIndex: 0, rect: CGRect(x: 586, y: 177, width: 199, height: 578)),
        RadianceTube(channelIndex: 1, rect: CGRect(x: 250, y: 180, width: 200, height: 576))
    ]
    static let radianceBars = [
        RadianceSimulatorBar(channelIndex: 0, anchorX: 656, anchorY: 285, direction: .down),
        RadianceSimulatorBar(channelIndex: 0, anchorX: 656, anchorY: 666, direction: .up),
        RadianceSimulatorBar(channelIndex: 1, anchorX: 320, anchorY: 285, direction: .down),
        RadianceSimulatorBar(channelIndex: 1, anchorX: 320, anchorY: 666, direction: .up)
    ]
    static let balanceGauges = [
        BalanceGauge(channelIndex: 1, rect: CGRect(x: 216, y: 70, width: 569, height: 217)),
        BalanceGauge(channelIndex: 0, rect: CGRect(x: 216, y: 578, width: 569, height: 218))
    ]
    static let balanceNeedles = [
        BalanceNeedleDefinition(channelIndex: 1, center: CGPoint(x: 502, y: 443), length: 333),
        BalanceNeedleDefinition(channelIndex: 0, center: CGPoint(x: 502, y: 951), length: 333)
    ]

    static func imagePixelSize(for moduleType: ModuleType) -> CGSize {
        switch moduleType {
        case .radiance, .unknown:
            return CGSize(width: 1000, height: 1000)
        case .balance:
            return CGSize(width: 1000, height: 1200)
        }
    }
}

private struct RadianceTube: Identifiable {
    let channelIndex: Int
    let rect: CGRect

    var id: Int { channelIndex }
}

private struct RadianceSimulatorBar: Identifiable {
    enum Direction: Hashable {
        case down
        case up
    }

    static let width: CGFloat = 58
    static let maxHeight: CGFloat = 190

    let channelIndex: Int
    let anchorX: CGFloat
    let anchorY: CGFloat
    let direction: Direction

    var id: String {
        "\(channelIndex)-\(anchorX)-\(anchorY)-\(direction)"
    }

    func rect(for percent: Double) -> CGRect {
        let height = max(0, min(1, percent)) * Self.maxHeight
        switch direction {
        case .down:
            return CGRect(x: anchorX, y: anchorY, width: Self.width, height: height)
        case .up:
            return CGRect(x: anchorX, y: anchorY - height, width: Self.width, height: height)
        }
    }
}

private struct RadianceDropTarget: Hashable, Identifiable {
    let moduleID: Int
    let channelIndex: Int

    var id: String {
        "\(moduleID)-\(channelIndex)"
    }
}

private struct BalanceGauge: Identifiable {
    let channelIndex: Int
    let rect: CGRect

    var id: Int { channelIndex }
}

private struct BalanceNeedleDefinition: Identifiable {
    let channelIndex: Int
    let center: CGPoint
    let length: CGFloat

    var id: Int { channelIndex }
}

private struct BalanceDropTarget: Hashable, Identifiable {
    let moduleID: Int
    let channelIndex: Int

    var id: String {
        "\(moduleID)-\(channelIndex)"
    }
}

private enum OverviewHotspot: Equatable {
    case source
    case radiance(RadianceDropTarget)
    case balance(BalanceDropTarget)
}

private enum MetricTokenKind: Hashable {
    case allEfficiency
    case allPerformance
    case memory
    case cpuCore(Int, CPUCoreKind)
}

private struct MetricToken: Identifiable, Hashable {
    let kind: MetricTokenKind

    var id: String {
        switch kind {
        case .allEfficiency:
            return "all-efficiency"
        case .allPerformance:
            return "all-performance"
        case .memory:
            return "memory"
        case .cpuCore(let index, _):
            return "cpu-\(index)"
        }
    }

    var label: String {
        switch kind {
        case .allEfficiency:
            return "小核平均"
        case .allPerformance:
            return "大核平均"
        case .memory:
            return "内存占用"
        case .cpuCore(let index, _):
            return "CPU\(index)"
        }
    }

    var width: CGFloat {
        switch kind {
        case .allEfficiency, .allPerformance, .memory:
            return 82
        case .cpuCore:
            return 58
        }
    }

    var color: Color {
        switch kind {
        case .allEfficiency:
            return Color(red: 0.42, green: 0.84, blue: 0.25)
        case .allPerformance:
            return Color(red: 0.95, green: 0.34, blue: 0.67)
        case .memory:
            return Color(red: 0.25, green: 0.62, blue: 0.95)
        case .cpuCore(_, let coreKind):
            return Self.color(for: coreKind)
        }
    }

    static func color(for coreKind: CPUCoreKind) -> Color {
        switch coreKind {
        case .efficiency:
            return Color(red: 0.42, green: 0.84, blue: 0.25)
        case .performance:
            return Color(red: 0.95, green: 0.34, blue: 0.67)
        case .unknown:
            return Color(red: 0.86, green: 0.73, blue: 0.36)
        }
    }
}

private struct BalanceMetricToken: Identifiable, Hashable {
    let kind: MetricSourceKind

    var id: String {
        Self.id(for: kind) ?? kind.rawValue
    }

    var label: String {
        switch kind {
        case .networkUp:
            return "网速上行"
        case .networkDown:
            return "网速下行"
        case .diskRead:
            return "硬盘读取"
        case .diskWrite:
            return "硬盘写入"
        default:
            return kind.label
        }
    }

    var metricKind: MetricSourceKind {
        kind
    }

    var color: Color {
        switch kind {
        case .networkUp, .networkDown:
            return Color(red: 0.26, green: 0.72, blue: 0.86)
        case .diskRead, .diskWrite:
            return Color(red: 0.92, green: 0.66, blue: 0.28)
        default:
            return Color(red: 0.62, green: 0.70, blue: 0.76)
        }
    }

    static func id(for kind: MetricSourceKind) -> String? {
        switch kind {
        case .networkUp:
            return "network-up"
        case .networkDown:
            return "network-down"
        case .diskRead:
            return "disk-read"
        case .diskWrite:
            return "disk-write"
        default:
            return nil
        }
    }
}
