import Foundation
import Capacitor
import UIKit

@objc(NativeSplashPlugin)
public class NativeSplashPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativeSplashPlugin"
    public let jsName = "NativeSplash"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "hide", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "show", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isVisible", returnType: CAPPluginReturnPromise)
    ]

    @objc func hide(_ call: CAPPluginCall) {
        let fadeOutDuration = call.getDouble("fadeOutDuration") ?? 200

        DispatchQueue.main.async {
            TidexContainerViewController.shared?.hideSplash(
                duration: fadeOutDuration / 1000.0
            ) {
                call.resolve()
            }
        }
    }

    @objc func show(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            TidexContainerViewController.shared?.showSplash()
            call.resolve()
        }
    }

    @objc func isVisible(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let visible = TidexContainerViewController.shared?.isSplashVisible() ?? false
            call.resolve(["visible": visible])
        }
    }
}
