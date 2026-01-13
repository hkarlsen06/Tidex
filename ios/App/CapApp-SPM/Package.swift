// swift-tools-version: 5.9
import PackageDescription

// DO NOT MODIFY THIS FILE - managed by Capacitor CLI commands
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.0.0"),
        .package(name: "CapacitorFirebaseMessaging", path: "../../../node_modules/.pnpm/@capacitor-firebase+messaging@8.0.1_@capacitor+core@8.0.0_firebase@12.7.0/node_modules/@capacitor-firebase/messaging"),
        .package(name: "CapacitorApp", path: "../../../node_modules/.pnpm/@capacitor+app@8.0.0_@capacitor+core@8.0.0/node_modules/@capacitor/app"),
        .package(name: "CapacitorBrowser", path: "../../../node_modules/.pnpm/@capacitor+browser@8.0.0_@capacitor+core@8.0.0/node_modules/@capacitor/browser"),
        .package(name: "CapacitorDevice", path: "../../../node_modules/.pnpm/@capacitor+device@8.0.0_@capacitor+core@8.0.0/node_modules/@capacitor/device"),
        .package(name: "CapacitorHaptics", path: "../../../node_modules/.pnpm/@capacitor+haptics@8.0.0_@capacitor+core@8.0.0/node_modules/@capacitor/haptics"),
        .package(name: "CapgoCapacitorSocialLogin", path: "../../../node_modules/.pnpm/@capgo+capacitor-social-login@8.2.13_@capacitor+core@8.0.0/node_modules/@capgo/capacitor-social-login"),
        .package(name: "CapgoNativePurchases", path: "../../../node_modules/.pnpm/@capgo+native-purchases@8.0.12_@capacitor+core@8.0.0/node_modules/@capgo/native-purchases")
    ],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "CapacitorFirebaseMessaging", package: "CapacitorFirebaseMessaging"),
                .product(name: "CapacitorApp", package: "CapacitorApp"),
                .product(name: "CapacitorBrowser", package: "CapacitorBrowser"),
                .product(name: "CapacitorDevice", package: "CapacitorDevice"),
                .product(name: "CapacitorHaptics", package: "CapacitorHaptics"),
                .product(name: "CapgoCapacitorSocialLogin", package: "CapgoCapacitorSocialLogin"),
                .product(name: "CapgoNativePurchases", package: "CapgoNativePurchases")
            ]
        )
    ]
)
