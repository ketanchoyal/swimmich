import AVKit
import SwiftUI

/// The system route picker, bridged for SwiftUI — the only UIKit bridge of the
/// cast feature, same family as `VideoPlayerLayerContainer`.
///
/// The control belongs to iOS: it lists the Apple TVs, AirPlay 2 TVs and AirPlay
/// boxes it found itself, shows its own "searching" state and performs the
/// connection. That is why the app draws no device list and why `CastService`
/// has no `connect()`.
struct RoutePickerView: UIViewRepresentable {

    /// Video first: this picker routes the viewer's stream, not audio.
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.activeTintColor = .white
        // A UIKit control carries no name for VoiceOver unless it is given one.
        picker.accessibilityLabel = String(localized: "Cast to a screen")
        return picker
    }

    /// Stateless on purpose: the route is published by `AirPlayCastService`, so
    /// this view has nothing to push back into the control.
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
