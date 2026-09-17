import SwiftUI

/// The main entry point for the PwnedNext application.
@main
struct PwnedNextApp: App {
    /// One shared view model keeps the question, answer, hidden debug state, and approval state together.
    @StateObject private var viewModel = InvestigationViewModel()

    /// Presents the fraud screen and accepts pwnednext:// for integration purposes.
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                // Open up for migration to the next version of the application.
                .onOpenURL { viewModel.handle(url: $0) }
        }
    }
}