import Capacitor
import UIKit
import QuickLook

/// Custom Capacitor plugin for sharing documents (PDF, CSV) via the native iOS Share Sheet.
/// This avoids the complexity of Capacitor's Filesystem + Share plugins by handling
/// everything in a single, purpose-built plugin.
@objc(DocumentSharePlugin)
public class DocumentSharePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DocumentSharePlugin"
    public let jsName = "DocumentShare"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "shareDocument", returnType: CAPPluginReturnPromise)
    ]

    private var currentTempURL: URL?
    private var currentCall: CAPPluginCall?

    /// Share a document via the native iOS Share Sheet.
    ///
    /// Parameters (in call.options):
    /// - `data`: Base64-encoded file content
    /// - `filename`: The filename including extension (e.g., "report.pdf")
    /// - `mimeType`: MIME type (e.g., "application/pdf", "text/csv")
    @objc func shareDocument(_ call: CAPPluginCall) {
        guard let base64Data = call.getString("data") else {
            call.reject("Missing 'data' parameter")
            return
        }

        guard let filename = call.getString("filename") else {
            call.reject("Missing 'filename' parameter")
            return
        }

        guard let data = Data(base64Encoded: base64Data) else {
            call.reject("Invalid base64 data")
            return
        }

        // Write to a unique subdirectory to avoid conflicts while keeping the original filename
        let uniqueDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
        let tempURL = uniqueDir.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)
        } catch {
            call.reject("Failed to write file: \(error.localizedDescription)")
            return
        }

        self.currentTempURL = tempURL
        self.currentCall = call

        // Present share sheet on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.reject("Plugin deallocated")
                return
            }

            guard let viewController = self.bridge?.viewController else {
                call.reject("No view controller available")
                self.cleanup()
                return
            }

            // Create activity view controller with the file URL
            let activityVC = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )

            // Exclude some activities that don't make sense for documents
            activityVC.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .postToFacebook,
                .postToTwitter,
                .postToWeibo,
                .postToVimeo,
                .postToTencentWeibo,
                .postToFlickr
            ]

            // Configure for iPad (prevent crash)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(
                    x: viewController.view.bounds.midX,
                    y: viewController.view.bounds.maxY - 100,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = [.down]
            }

            // Set modal presentation style to cover full screen
            activityVC.modalPresentationStyle = .pageSheet

            // Completion handler to clean up temp file
            activityVC.completionWithItemsHandler = { [weak self] activityType, completed, returnedItems, error in
                self?.cleanup()

                if let error = error {
                    self?.currentCall?.reject("Share failed: \(error.localizedDescription)")
                } else {
                    self?.currentCall?.resolve([
                        "completed": completed,
                        "activityType": activityType?.rawValue ?? ""
                    ])
                }
                self?.currentCall = nil
            }

            viewController.present(activityVC, animated: true)
        }
    }

    private func cleanup() {
        if let url = currentTempURL {
            let tempDir = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: tempDir)
            currentTempURL = nil
        }
    }
}
