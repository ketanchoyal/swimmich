import SwiftUI
import UIKit

/// Non-destructive photo editor (cahier §5 L117-130).
///
/// MVP scope: crop (rule-of-thirds + predefined ratios), rotation fine slider (-45..+45)
/// + 90° buttons, adjustments (exposure/contrast/saturation/warmth), local EditState persistence,
/// "Revenir à l'original". Auto-saves on disappear.
struct PhotoEditorView: View {
    @Bindable var vm: PhotoEditorViewModel
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewSection
                    CropAspectPickerView(selectedRatio: Binding(
                        get: { vm.editState.aspectRatio },
                        set: { vm.setAspectRatio($0) }
                    ))
                    RotationSliderView(
                        straightenDeg: Binding(
                            get: { vm.editState.straightenDeg },
                            set: { vm.setStraighten($0) }
                        ),
                        onRotate90CW: { vm.rotate90CW() },
                        onRotate90CCW: { vm.rotate90CCW() }
                    )
                    AdjustmentSlidersView(
                        exposure: Binding(get: { vm.editState.exposure }, set: { vm.setExposure($0) }),
                        contrast: Binding(get: { vm.editState.contrast }, set: { vm.setContrast($0) }),
                        saturation: Binding(get: { vm.editState.saturation }, set: { vm.setSaturation($0) }),
                        warmth: Binding(get: { vm.editState.warmth }, set: { vm.setWarmth($0) })
                    )
                    Button("Revenir à l'original") {
                        vm.resetToOriginal()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!vm.canRevert)
                    .accessibilityIdentifier("revertToOriginalButton")

                    if let err = vm.errorMessage {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
                .padding()
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // AC-616: load on appear.
            if let baseURL = auth.baseURL {
                let url = ImmichAssetURL.original(assetId: vm.assetId, baseURL: baseURL)
                await vm.loadOriginal(url: url, token: auth.accessToken)
                await vm.loadState()
            }
        }
        .onDisappear {
            // AC-616: save on disappear.
            vm.saveState()
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        GeometryReader { geo in
            ZStack {
                if let img = vm.previewImage ?? vm.originalImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.width)
                } else if vm.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView("No Image", systemImage: "photo")
                }
                if vm.isGridVisible {
                    RuleOfThirdsOverlay()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .accessibilityIdentifier("ruleOfThirdsOverlay")
                }
            }
        }
        .frame(height: UIScreen.main.bounds.width)
    }
}

// MARK: - RuleOfThirdsOverlay (AC-608)

struct RuleOfThirdsOverlay: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1)
            let thirdsX = size.width / 3
            let thirdsY = size.height / 3
            var path = Path()
            // Vertical lines
            path.move(to: CGPoint(x: thirdsX, y: 0))
            path.addLine(to: CGPoint(x: thirdsX, y: size.height))
            path.move(to: CGPoint(x: 2 * thirdsX, y: 0))
            path.addLine(to: CGPoint(x: 2 * thirdsX, y: size.height))
            // Horizontal lines
            path.move(to: CGPoint(x: 0, y: thirdsY))
            path.addLine(to: CGPoint(x: size.width, y: thirdsY))
            path.move(to: CGPoint(x: 0, y: 2 * thirdsY))
            path.addLine(to: CGPoint(x: size.width, y: 2 * thirdsY))
            context.stroke(path, with: .color(.white.opacity(0.6)), style: stroke)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - RotationSliderView (AC-609)

struct RotationSliderView: View {
    @Binding var straightenDeg: Double
    let onRotate90CW: () -> Void
    let onRotate90CCW: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rotation").font(.headline)
            HStack {
                Button(action: onRotate90CCW) {
                    Image(systemName: "rotate.left")
                }
                .accessibilityIdentifier("rotate90CCWButton")
                Slider(value: $straightenDeg, in: -45...45, step: 1) {
                    Text("Straighten")
                }
                Text(String(format: "%+.0f°", straightenDeg))
                    .frame(width: 48, alignment: .trailing)
                    .font(.caption.monospacedDigit())
                Button(action: onRotate90CW) {
                    Image(systemName: "rotate.right")
                }
                .accessibilityIdentifier("rotate90CWButton")
            }
        }
    }
}

// MARK: - AdjustmentSlidersView (AC-610)

struct AdjustmentSlidersView: View {
    @Binding var exposure: Double
    @Binding var contrast: Double
    @Binding var saturation: Double
    @Binding var warmth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adjustments").font(.headline)
            adjustmentRow(label: "Exposure", value: $exposure, range: -2...2)
            adjustmentRow(label: "Contrast", value: $contrast, range: -1...1)
            adjustmentRow(label: "Saturation", value: $saturation, range: -1...1)
            adjustmentRow(label: "Warmth", value: $warmth, range: -1...1)
        }
    }

    private func adjustmentRow(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range, step: 0.05)
            Text(String(format: "%+.2f", value.wrappedValue))
                .frame(width: 56, alignment: .trailing)
                .font(.caption.monospacedDigit())
        }
    }
}

// MARK: - CropAspectPickerView (AC-611)

struct CropAspectPickerView: View {
    @Binding var selectedRatio: CropAspectRatio?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crop Ratio").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CropAspectRatio.allCases, id: \.self) { ratio in
                        Button {
                            selectedRatio = (selectedRatio == ratio) ? nil : ratio
                        } label: {
                            Text(displayName(ratio))
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedRatio == ratio ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .accessibilityIdentifier("ratioButton.\(ratio.rawValue)")
                    }
                }
            }
        }
    }

    private func displayName(_ r: CropAspectRatio) -> String {
        switch r {
        case .freeform:     return "Free"
        case .square:       return "1:1"
        case .fourByThree:  return "4:3"
        case .threeByTwo:   return "3:2"
        case .twoByThree:   return "2:3"
        case .sixteenByNine: return "16:9"
        case .nineBySixteen: return "9:16"
        }
    }
}
