import PackageDescription

let package = Package(
    name: "SQLite",
    dependencies: [
        .Package(url: "https://github.com/vapor/csqlite.git", majorVersion: 1),
        .Package(url: "https://github.com/vapor/core.git", majorVersion: 1),

    ]
)