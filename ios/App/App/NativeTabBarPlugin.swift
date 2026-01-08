import Foundation
import Capacitor

@objc(NativeTabBarPlugin)
public class NativeTabBarPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "NativeTabBarPlugin"
    public let jsName = "NativeTabBar"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setSelectedTab", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearSelection", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTabBadge", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTabTitles", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hide", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "show", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getTabBarHeight", returnType: CAPPluginReturnPromise)
    ]

    weak var containerController: TidexContainerViewController?

    @objc func setSelectedTab(_ call: CAPPluginCall) {
        guard let index = call.getInt("index") else {
            call.reject("Missing index")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.containerController?.setSelectedTabIndex(index)
            call.resolve()
        }
    }

    @objc func clearSelection(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            self?.containerController?.clearSelection()
            call.resolve()
        }
    }

    @objc func setTabBadge(_ call: CAPPluginCall) {
        guard let index = call.getInt("index") else {
            call.reject("Missing index")
            return
        }
        let value = call.getString("value")
        DispatchQueue.main.async { [weak self] in
            self?.containerController?.setTabBadge(index: index, value: value)
            call.resolve()
        }
    }

    @objc func setTabTitles(_ call: CAPPluginCall) {
        guard let titles = call.getArray("titles", String.self) else {
            call.reject("Missing titles array")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.containerController?.setTabTitles(titles)
            call.resolve()
        }
    }

    @objc func hide(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            self?.containerController?.hideTabBar()
            call.resolve()
        }
    }

    @objc func show(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            self?.containerController?.showTabBar()
            call.resolve()
        }
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["available": containerController != nil])
    }

    @objc func getTabBarHeight(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            let height = self?.containerController?.getTabBarHeight() ?? 0
            call.resolve(["height": height])
        }
    }

    // Called from TidexContainerViewController when tab is tapped
    func handleTabSelection(index: Int, route: String) {
        notifyListeners("tabSelected", data: [
            "index": index,
            "route": route
        ])
    }

    // Called from TidexContainerViewController when same tab is re-tapped
    func handleTabReselection(index: Int, route: String) {
        notifyListeners("tabReselected", data: [
            "index": index,
            "route": route
        ])
    }
}
