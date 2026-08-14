import SwiftUI

@main
struct MMoveApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("mmove")
        } label: {
            Image(systemName: "computermouse")
        }
        .menuBarExtraStyle(.menu)
    }
}
