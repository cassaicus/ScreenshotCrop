import SwiftUI
// Import AppKit framework for NSWorkspace
import AppKit
// Import ApplicationServices for Accessibility APIs
import ApplicationServices

/// View for configuring auto-screenshot settings
struct AutoScreenshotSettingsView: View {
    @EnvironmentObject var store: ImageStore
    @ObservedObject var manager: AutoScreenshotManager

    init(manager: AutoScreenshotManager) {
        self.manager = manager
    }

    var body: some View {
        Text("To take a screenshot, click on the floating panel or use the automatic mode below.")
        VStack(alignment: .leading, spacing: 10) {
            Text("automatic mode")
            // Row 1: Accessibility Approval
            HStack {
                Button("Grant Accessibility") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    AXIsProcessTrustedWithOptions(options as CFDictionary)
                    
                    // Open Accessibility settings
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Key Input Direction")
                .font(.caption)
            // Row 2: Direction Picker
            HStack {
                Picker("", selection: $manager.autoCaptureDirection) {
                    Text("←").tag("left")
                    Text("↑").tag("up")
                    Text("↓").tag("down")
                    Text("→").tag("right")
                }
                .pickerStyle(.segmented)
                .disabled(manager.isAutoCapturing)
            }

            // Row 3: Capture Interval
            HStack {
                Text("Interval")
                    .font(.caption)
                Spacer()
                Stepper(value: $manager.autoCaptureInterval, in: 0.1...10.0, step: 0.1) {
                    Text("\(String(format: "%.1f", manager.autoCaptureInterval))sec")
                        .monospacedDigit()
                }
                .disabled(manager.isAutoCapturing)
            }

            // Row 4: Stop Condition
            VStack(alignment: .leading, spacing: 4) {
                Text("Stop Condition (Overlap Threshold)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Slider(value: $manager.autoCaptureThreshold, in: 0.0...1.0)
                        .disabled(manager.isAutoCapturing)
                    Text("\(Int(manager.autoCaptureThreshold * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            // Row 5: Start/Stop Button
            Button(action: {
                if manager.isAutoCapturing {
                    manager.stopAutoCapture()
                } else {
                    manager.startAutoCapture()
                }
            }) {
                Group {
                    if let countdown = manager.countdownRemaining {
                        Text("\(countdown)")
                    } else {
                        Text(manager.isAutoCapturing ? "Stop Capture" : "Start Capture")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.isAutoCapturing ? .red : .blue)
            .disabled(store.screenshotFolderURL == nil)
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    let store = ImageStore()
    AutoScreenshotSettingsView(manager: store.autoManager)
        .environmentObject(store)
        .frame(width: 250)
        .padding()
}
