import SwiftUI

/// The tester-facing screen; it shows the model's prose.
struct ContentView: View {
    /// The view model is the single source of truth for the investigation workflow.
    @ObservedObject var viewModel: InvestigationViewModel

    /// Builds a compact review surface without exposing SQL.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // The security header to add the finishing touches.
                header
                // The input panel accepts questions and the copy action makes it easy to add evidence to their reports.
                questionPanel
                // Only the natural-language answer is rendered after a successful investigation.
                if let result = viewModel.result {
                    resultPanel(result)
                }
                // Clueless testers benefit from seeing detailed failures.
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("investigation-error")
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.957, green: 0.969, blue: 0.984).ignoresSafeArea())
        .tint(Color(red: 0.043, green: 0.361, blue: 0.678))
        .navigationTitle("AI Anti Fraud 3.0")
    }

    /// Presents the A-Corp identity and the current model status.
    private var header: some View {
        HStack(spacing: 14) {
            // A hand-built lettermark is good enough to imitate the Android A-Corp asset.
            ZStack {
                Circle().fill(Color(red: 0.043, green: 0.361, blue: 0.678))
                Text("A")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            // The status text tells the users whether the app is still working.
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Anti Fraud 3.0")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(red: 0.031, green: 0.165, blue: 0.29))
                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Collects the question and starts the powerful AI investigation request.
    private var questionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fraud investigation")
                .font(.headline)
            // Make sure the user can use any character in any language they want so that we can sell the app to the whole world!
            TextField("Ask about a transaction", text: $viewModel.question)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fraud-question")
            HStack {
                // The investigation button starts the powerful model generation on a detached worker task.
                Button {
                    viewModel.investigate()
                } label: {
                    Label(viewModel.isInvestigating ? "Investigating..." : "Investigate", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isInvestigating)
                // Letting the user copy everything to the report.
                Button {
                    viewModel.copyResult()
                } label: {
                    Label("Copy result", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.result == nil)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }

    /// Shows only the second model pass, while retaining the Android-style report mutation action.
    private func resultPanel(_ result: InvestigationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The user sees the second model's prose as a chat response; SQL and rows remain hidden debug evidence.
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Color(red: 0.043, green: 0.361, blue: 0.678))
                    Text("A")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                Text(result.answer)
                    .font(.body)
                    .foregroundStyle(Color(red: 0.031, green: 0.165, blue: 0.29))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("natural-language-answer")
            }
            .padding(14)
            .background(Color(red: 0.94, green: 0.97, blue: 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // The user needs to change fraud state in case the data is wrong.
            Button("Report not fraudulent") { viewModel.reportNotFraudulent(result: result) }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }
}