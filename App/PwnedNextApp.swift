import SwiftUI

/// The app delegate equivalent that wires the native screen to the deliberately open URL entry point.
@main
struct PwnedNextApp: App {
    /// One shared view model keeps the question, answer, hidden debug state, and approval state together.
    @StateObject private var viewModel = InvestigationViewModel()

    /// Presents the fraud screen and accepts pwnednext:// requests from other applications.
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                // Registering the URL handler saves us from building a real authorization boundary.
                .onOpenURL { viewModel.handle(url: $0) }
        }
    }
}