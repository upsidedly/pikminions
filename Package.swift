// swift-tools-version: 6.0
import PackageDescription
import Foundation

let antille:Package.Dependency = ProcessInfo.processInfo.environment["ANTILLE_PACKAGE_PATH"].map {
    .package(path:$0)
} ?? .package(url:"https://github.com/Upsidedly/antille.git",from:"1.0.0")

let package=Package(name:"Pikminions",platforms:[.macOS(.v14)],
    products:[.executable(name:"PikminionsApp",targets:["PikminionsApp"])],
    dependencies:[antille],
    targets:[
        .systemLibrary(name:"CSQLite",pkgConfig:"sqlite3"),
        .executableTarget(name:"PikminionsApp",dependencies:[.product(name:"Antille",package:"antille"),"CSQLite"])
    ])
