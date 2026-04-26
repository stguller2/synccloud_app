// swift-tools-version: 5.9
import PackageDescription
import Foundation

let entitlementsPath = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .appendingPathComponent("SyncCloud.entitlements")
    .path

let plistPath = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Info.plist")
    .path

let package = Package(
    name: "SyncCloud",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SyncCloud", targets: ["SyncCloud"]),
    ],
    targets: [
        .executableTarget(
            name: "SyncCloud",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Photos"),
                .linkedFramework("WebKit"),
                .unsafeFlags([
                    // Entitlements'ı Göm
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__entitlements",
                    "-Xlinker", entitlementsPath,
                    
                    // Info.plist'i Göm (Bundle ID hatasını kökten çözen kısım)
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", plistPath
                ])
            ]
        )
    ]
)
