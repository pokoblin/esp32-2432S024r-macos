// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sysmon",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SysmonCore"),
        .executableTarget(name: "Sysmon", dependencies: ["SysmonCore"]),
        .testTarget(name: "SysmonCoreTests", dependencies: ["SysmonCore"]),
    ]
)
