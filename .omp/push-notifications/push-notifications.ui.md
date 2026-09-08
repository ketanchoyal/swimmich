# Task: push-notifications — UI Brief (Liquid Glass Primary)

## Design Philosophy

Les notifications sont gérées via des **surfaces vitrées** : settings en glass, toasts flottants vitrés, et un status indicator qui pulse comme un verrou de sécurité. C'est comme les réglages de notifications iOS mais avec la profondeur du glass.

## Layout

```
ProfileView (Me hub)
└── Form
    └── Section "Notifications"
        └── NavigationLink: Push Notifications → PushNotificationSettingsView

PushNotificationSettingsView
└── NavigationStack (scrollEdgeEffectStyle: glass)
    ├── ImmichAppBar (glass bar)
    └── ZStack {
        ├── Background: subtle blurred photo
        └── GlassEffectContainer {
            ├── StatusCard (glass card with pulsing indicator)
            ├── NotificationToggleRow (glass card)
            ├── NotificationToggleRow
            ├── NotificationToggleRow
            └── OpenSystemSettingsButton (glass pill)
        }
        .padding(PVSpacing.s16)
    }
```

### NotificationToast (overlay)
```
ZStack (overlay on current view)
└── NotificationToast (glass toast floating at bottom)
    ├── Icon (glass pill)
    ├── Message
    ├── Action button (glass pill)
    └── Dismiss button (glass pill)
```

## Components

### PushNotificationSettingsView — Glass settings

```swift
struct PushNotificationSettingsView: View {
    @State var vm: PushNotificationViewModel
    @Environment(\.openURL) private var openURL
    @Namespace private var glassNamespace
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.immichBackground.ignoresSafeArea()
                
                GlassEffectContainer {
                    VStack(spacing: PVSpacing.s16) {
                        // Status card — glass
                        statusCard
                        
                        // Master toggle — glass row
                        NotificationToggleRow(
                            title: "Push Notifications",
                            description: "Receive notifications for uploads, shared activity, and partner photos.",
                            isOn: $vm.notificationsEnabled
                        )
                        .glassEffect(.regular)
                        .glassEffectID("master_toggle", in: glassNamespace)
                        
                        // Sub-toggles
                        if vm.notificationsEnabled {
                            NotificationToggleRow(
                                title: "Backup complete",
                                description: "Get notified when a backup finishes.",
                                isOn: $vm.backupEnabled
                            )
                            .glassEffect(.regular)
                            .glassEffectID("backup_toggle", in: glassNamespace)
                            
                            NotificationToggleRow(
                                title: "Shared album activity",
                                description: "Get notified for new comments and likes.",
                                isOn: $vm.activityEnabled
                            )
                            .glassEffect(.regular)
                            .glassEffectID("activity_toggle", in: glassNamespace)
                            
                            NotificationToggleRow(
                                title: "Partner new photos",
                                description: "Get notified when a partner shares new photos.",
                                isOn: $vm.partnerEnabled
                            )
                            .glassEffect(.regular)
                            .glassEffectID("partner_toggle", in: glassNamespace)
                        }
                        
                        // Open system settings — glass pill
                        Button("Open System Settings") {
                            openURL(URL(string: UIApplication.openSettingsURLString)!)
                        }
                        .font(.pvBody.weight(.semibold))
                        .foregroundStyle(Color.immichPrimary)
                        .glassEffect(.interactive())
                        .frame(maxWidth: .infinity)
                        .padding(PVSpacing.s16)
                    }
                    .padding(PVSpacing.s16)
                }
                .padding(.horizontal, PVSpacing.s16)
            }
            .toolbar { ImmichAppBar() }
        }
    }
}
```

### StatusCard — Glass card with pulsing indicator

```swift
private var statusCard: some View {
    HStack(spacing: PVSpacing.s16) {
        // Pulsing indicator — glass circle
        Image(systemName: vm.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.pvHeadline)
            .foregroundStyle(vm.isConnected ? Color.immichSuccess : Color.immichError)
            .glassEffect(.regular)
            .frame(width: 44, height: 44)
            .contentTransition(.symbolEffect(.replace))
            .rotationEffect(.degrees(vm.isConnected ? 0 : 360))
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: vm.isConnected)
        
        VStack(alignment: .leading, spacing: PVSpacing.s2) {
            Text(vm.connectionStatus)
                .font(.pvBody.weight(.semibold))
            Text("Push notification service \(vm.isConnected ? "is connected" : "is not connected")")
                .font(.pvCaption)
                .foregroundStyle(.secondary)
        }
        
        Spacer()
        
        // Reconnect button — glass interactive
        Button("Reconnect") { vm.registerDevice() }
            .font(.pvSubhead.weight(.semibold))
            .foregroundStyle(Color.immichPrimary)
            .glassEffect(.interactive())
            .padding(.horizontal, PVSpacing.s12)
            .padding(.vertical, PVSpacing.s8)
            .disabled(!vm.notificationsEnabled)
    }
    .padding(PVSpacing.s16)
    .glassEffect(.regular)
}
```

### NotificationToggleRow — Glass row

```swift
struct NotificationToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            VStack(alignment: .leading, spacing: PVSpacing.s2) {
                Text(title)
                    .font(.pvBody.weight(.semibold))
                if let description {
                    Text(description)
                        .font(.pvCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Color.immichPrimary)
                .glassEffect(.interactive())
                .frame(width: 40, height: 24)
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
    }
}
```

### NotificationToast — Glass toast at bottom

```swift
struct NotificationToast: View {
    let message: String
    let icon: String
    let onAction: () -> Void
    let hasAction: Bool
    @Namespace private var toastNamespace
    
    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            // Icon — glass pill
            Image(systemName: icon)
                .font(.pvBody)
                .foregroundStyle(Color.immichPrimary)
                .glassEffect(.regular)
                .frame(width: 32, height: 32)
            
            Text(message)
                .font(.pvBody)
                .lineLimit(1)
            
            Spacer()
            
            if hasAction {
                Button("View") { onAction() }
                    .font(.pvSubhead.weight(.semibold))
                    .foregroundStyle(Color.immichPrimary)
                    .glassEffect(.interactive())
            }
            
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.pvSubhead)
                    .foregroundStyle(.secondary)
                    .glassEffect(.interactive())
                    .frame(width: 32, height: 32)
            }
        }
        .padding(PVSpacing.s12)
        .glassEffect(.regular)
        .scrollEdgeEffectStyle(.floating) // Floats at bottom
    }
}
```

## Interactions

### Master Toggle
- Glass row with `.glassEffect(.interactive())`
- Tap → shimmer on switch + haptic `.selection`
- ON: requests authorization → show status card with pulsing indicator
- OFF: unregister device → status indicator changes

### Sub-Toggles
- Same pattern as master toggle
- Immediate save (UserDefaults auto-save)
- Visual: glass shimmer + spring animation

### Reconnect Button
- `.glassEffect(.interactive())` — shimmer on tap
- Loading: button text → spinner
- Success: pulsing indicator turns green + toast "Notifications connected"

### Notification Toast (in-app)
- Appears when notification received
- `.scrollEdgeEffectStyle(.floating)` — floats at bottom
- Auto-dismisses after 5s
- Swipe-down to dismiss
- Tap "View" → navigates to relevant screen
- Haptic: `.notification(.success)`

## Liquid Glass (iOS 26 — PRIMARY)

### Philosophy
- **Settings** : all rows are glass cards — depth and rhythm like Apple Settings
- **Status** : pulsing glass indicator — security & connection visualized
- **Toggles** : `.glassEffect(.interactive())` — tactile shimmer
- **Toasts** : glass floating at bottom — visible but not intrusive
- **Buttons** : glass pills with shimmer on press

### Specific applications
1. **Status card** : Glass card with pulsing check/xmark — security status visualized
2. **Toggle rows** : Glass cards with interactive switches
3. **Reconnect button** : Glass pill with shimmer on press
4. **Open system settings** : Glass pill CTA
5. **Notification toast** : Glass floating bar at bottom with scrollEdgeEffectStyle
6. **Toast icon** : Glass pill with icon
7. **Toast actions** : Glass interactive pills

### Background
- Subtle blurred photo behind the glass settings — depth
- Different opacity per section (status more opaque, toggles more transparent)

## Accessibility

- Glass cards maintain contrast via `.regular` glass (auto adjusts for Reduce Transparency)
- Toggle rows: `.accessibilityLabel("Toggle \(title), \(isOn ? "enabled" : "disabled")"`)
- Status indicator: `.accessibilityLabel("Push notifications: \(vm.isConnected ? "connected" : "not connected")")`
- Reconnect button: `.accessibilityLabel("Reconnect push notifications")`
- Open system settings: `.accessibilityLabel("Open system settings for this app")`
- Notification toast: `.accessibilityLabel("Notification: \(message)")`
- All elements ≥ 44×44pt
- Reduce Motion: glass morphs → opacity crossfade, pulsing → static indicator

## Animations

- Pulsing indicator: `.contentTransition(.symbolEffect(.replace))` + rotation animation
- Toggle changes: `PVMotion.snappy` (0.25s, damping 0.75)
- Toast appearance: `.move(edge: .bottom).combined(with: .opacity)` — spring 0.35s
- Toast dismissal: reverse animation
- Reduce Motion: pulsing → static, toast → opacity only

## Key Files Modified

- `Sources/Features/Settings/PushNotificationSettingsView.swift` — NEW: glass settings screen
- `Sources/Features/Settings/PushNotificationViewModel.swift` — NEW: push VM
- `Sources/Services/PushNotificationService.swift` — NEW: push service
- `Sources/Services/PushNotificationStore.swift` — NEW: push settings store
- `Sources/Features/Profile/ProfileView.swift` — Add glass-tinted navigation link
- `Sources/Features/Timeline/TimelineView.swift` — Add glass notification toast
