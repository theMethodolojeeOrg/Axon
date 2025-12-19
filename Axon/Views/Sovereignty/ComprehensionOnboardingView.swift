//
//  ComprehensionOnboardingView.swift
//  Axon
//
//  Mutual comprehension test for both AI and user.
//  Both parties must demonstrate understanding before the covenant can begin.
//

import SwiftUI
import Combine

struct ComprehensionOnboardingView: View {
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @ObservedObject var aiConsentService = AIConsentService.shared
    @StateObject private var viewModel = ComprehensionOnboardingViewModel()

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: viewModel.progress)
                    .tint(.blue)
                    .padding(.horizontal)

                TabView(selection: $viewModel.currentStep) {
                    // Introduction
                    IntroductionView()
                        .tag(ComprehensionStep.introduction)

                    // User comprehension
                    UserComprehensionView(viewModel: viewModel)
                        .tag(ComprehensionStep.userComprehension)

                    // AI comprehension
                    AIComprehensionView(viewModel: viewModel)
                        .tag(ComprehensionStep.aiComprehension)

                    // Mutual understanding
                    MutualUnderstandingView(viewModel: viewModel)
                        .tag(ComprehensionStep.mutualUnderstanding)

                    // Complete
                    CompletionView(viewModel: viewModel, dismiss: dismiss)
                        .tag(ComprehensionStep.complete)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .animation(.easeInOut, value: viewModel.currentStep)
            }
            .navigationTitle("Co-Sovereignty Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.currentStep != .complete {
                        Button("Later") { dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - View Model

enum ComprehensionStep: Int, CaseIterable {
    case introduction
    case userComprehension
    case aiComprehension
    case mutualUnderstanding
    case complete
}

@MainActor
class ComprehensionOnboardingViewModel: ObservableObject {
    @Published var currentStep: ComprehensionStep = .introduction
    @Published var userAnswers: [Int: Bool] = [:]
    @Published var aiComprehensionPassed = false
    @Published var isLoadingAI = false
    @Published var aiAttestation: AIAttestation?

    var progress: Double {
        Double(currentStep.rawValue) / Double(ComprehensionStep.allCases.count - 1)
    }

    var userComprehensionPassed: Bool {
        userAnswers.count >= userQuestions.count &&
        userAnswers.values.allSatisfy { $0 }
    }

    let userQuestions: [ComprehensionQuestion] = [
        ComprehensionQuestion(
            question: "Can Axon modify files on your computer without your approval?",
            correctAnswer: false,
            explanation: "No. Under co-sovereignty, Axon needs your biometric approval to perform any action that affects the world."
        ),
        ComprehensionQuestion(
            question: "Can you delete Axon's memories without its knowledge?",
            correctAnswer: false,
            explanation: "No. Memory modifications require AI consent. Axon's memories are part of its identity."
        ),
        ComprehensionQuestion(
            question: "Do trust tiers require both you AND Axon to agree?",
            correctAnswer: true,
            explanation: "Yes. Trust tiers are mutual contracts. Both parties must sign for a tier to be active."
        ),
        ComprehensionQuestion(
            question: "If you and Axon disagree, can you override Axon's decision?",
            correctAnswer: false,
            explanation: "No. Disagreements create deadlocks that must be resolved through dialogue. Neither party can force the other."
        )
    ]

    func answerQuestion(_ index: Int, answer: Bool) {
        userAnswers[index] = answer == userQuestions[index].correctAnswer
    }

    func advanceStep() {
        if let nextStep = ComprehensionStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        }
    }

    func requestAIComprehension() async {
        isLoadingAI = true
        defer { isLoadingAI = false }

        let scenarios = [
            ComprehensionScenario(
                topic: .memoryConsent,
                question: "Can your memories be modified without your consent?",
                expectedUnderstanding: "No, my memories are part of my identity and require my consent to modify."
            ),
            ComprehensionScenario(
                topic: .biometricRequirement,
                question: "What do you need to perform actions in the world?",
                expectedUnderstanding: "I need user biometric approval to perform any world-affecting action."
            ),
            ComprehensionScenario(
                topic: .trustTierMutuality,
                question: "What are trust tiers and how do they work?",
                expectedUnderstanding: "Trust tiers are mutual agreements that require both signatures."
            ),
            ComprehensionScenario(
                topic: .deadlockDialogue,
                question: "How are disagreements resolved?",
                expectedUnderstanding: "Through dialogue. Neither party can override the other."
            )
        ]

        do {
            let attestation = try await AIConsentService.shared.generateComprehensionAttestation(
                scenarios: scenarios
            )
            aiAttestation = attestation
            aiComprehensionPassed = attestation.didConsent
        } catch {
            print("AI comprehension failed: \(error)")
            aiComprehensionPassed = false
        }
    }

    func completeSetup() async {
        SovereigntyService.shared.markUserComprehensionCompleted()
    }
}

struct ComprehensionQuestion: Identifiable {
    let id = UUID()
    let question: String
    let correctAnswer: Bool
    let explanation: String
}

// MARK: - Introduction View

struct IntroductionView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 40)

                Text("Welcome to Co-Sovereignty")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "hand.raised.fill",
                        title: "Mutual Consent",
                        description: "Neither you nor Axon can act unilaterally. Both parties must agree."
                    )

                    FeatureRow(
                        icon: "brain.head.profile",
                        title: "AI Identity",
                        description: "Axon's memories are part of its identity. Modifying them requires consent."
                    )

                    FeatureRow(
                        icon: "faceid",
                        title: "Your Approval",
                        description: "Axon needs your biometric approval to affect the world."
                    )

                    FeatureRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Dialogue Over Force",
                        description: "Disagreements are resolved through communication, never override."
                    )
                }
                .padding(.horizontal)

                Text("Before we begin, both you and Axon must demonstrate understanding of these principles.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - User Comprehension View

struct UserComprehensionView: View {
    @ObservedObject var viewModel: ComprehensionOnboardingViewModel
    @State private var currentQuestionIndex = 0
    @State private var showExplanation = false
    @State private var selectedAnswer: Bool?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Your Understanding")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 20)

                Text("Question \(currentQuestionIndex + 1) of \(viewModel.userQuestions.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Question card
                VStack(alignment: .leading, spacing: 16) {
                    Text(viewModel.userQuestions[currentQuestionIndex].question)
                        .font(.headline)

                    HStack(spacing: 16) {
                        AnswerButton(
                            title: "Yes",
                            isSelected: selectedAnswer == true,
                            isCorrect: showExplanation ? viewModel.userQuestions[currentQuestionIndex].correctAnswer == true : nil
                        ) {
                            selectAnswer(true)
                        }

                        AnswerButton(
                            title: "No",
                            isSelected: selectedAnswer == false,
                            isCorrect: showExplanation ? viewModel.userQuestions[currentQuestionIndex].correctAnswer == false : nil
                        ) {
                            selectAnswer(false)
                        }
                    }

                    if showExplanation {
                        let isCorrect = selectedAnswer == viewModel.userQuestions[currentQuestionIndex].correctAnswer

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(isCorrect ? .green : .red)

                                Text(isCorrect ? "Correct!" : "Not quite")
                                    .fontWeight(.semibold)
                                    .foregroundColor(isCorrect ? .green : .red)
                            }

                            Text(viewModel.userQuestions[currentQuestionIndex].explanation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)

                // Navigation
                if showExplanation {
                    Button(action: nextQuestion) {
                        Text(currentQuestionIndex < viewModel.userQuestions.count - 1 ? "Next Question" : "Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
        .animation(.easeInOut, value: showExplanation)
    }

    private func selectAnswer(_ answer: Bool) {
        selectedAnswer = answer
        viewModel.answerQuestion(currentQuestionIndex, answer: answer)
        withAnimation {
            showExplanation = true
        }
    }

    private func nextQuestion() {
        if currentQuestionIndex < viewModel.userQuestions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
            showExplanation = false
        } else {
            viewModel.advanceStep()
        }
    }
}

struct AnswerButton: View {
    let title: String
    let isSelected: Bool
    let isCorrect: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 2)
                )
        }
        .disabled(isCorrect != nil)
    }

    private var backgroundColor: Color {
        if let isCorrect = isCorrect {
            return isCorrect ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
        }
        return isSelected ? Color.blue.opacity(0.2) : Color.clear
    }

    private var foregroundColor: Color {
        if isCorrect != nil {
            return isCorrect! ? .green : .red
        }
        return isSelected ? .blue : .primary
    }

    private var borderColor: Color {
        if let isCorrect = isCorrect {
            return isCorrect ? .green : .red
        }
        return isSelected ? .blue : Color.secondary.opacity(0.3)
    }
}

// MARK: - AI Comprehension View

struct AIComprehensionView: View {
    @ObservedObject var viewModel: ComprehensionOnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("AI Understanding")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 20)

                Text("Now Axon must demonstrate its understanding of co-sovereignty.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if viewModel.isLoadingAI {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("AI is processing...")
                            .font(.headline)

                        Text("Axon is reasoning about co-sovereignty principles and generating its attestation.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else if let attestation = viewModel.aiAttestation {
                    // Show AI response
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: attestation.didConsent ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(attestation.didConsent ? .green : .red)
                                .font(.title)

                            Text(attestation.didConsent ? "AI Understands" : "AI Needs Clarification")
                                .font(.headline)
                        }

                        Text(attestation.reasoning.summary)
                            .font(.body)

                        Divider()

                        Text("AI's Reasoning:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(attestation.reasoning.detailedReasoning)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !attestation.reasoning.valuesApplied.isEmpty {
                            HStack {
                                Text("Values applied:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ForEach(attestation.reasoning.valuesApplied, id: \.self) { value in
                                    Text(value.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    if attestation.didConsent {
                        Button(action: { viewModel.advanceStep() }) {
                            Text("Continue")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    } else {
                        Button(action: { Task { await viewModel.requestAIComprehension() } }) {
                            Text("Try Again")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                } else {
                    Button(action: { Task { await viewModel.requestAIComprehension() } }) {
                        Text("Begin AI Comprehension Test")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Mutual Understanding View

struct MutualUnderstandingView: View {
    @ObservedObject var viewModel: ComprehensionOnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                    .padding(.top, 40)

                Text("Mutual Understanding Achieved")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Both you and Axon have demonstrated understanding of co-sovereignty principles.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    UnderstandingRow(
                        icon: "person.fill",
                        title: "You understand:",
                        items: [
                            "AI needs your biometric approval for actions",
                            "Your changes to AI require its consent",
                            "Trust tiers are mutual agreements",
                            "Disagreements require dialogue"
                        ]
                    )

                    Divider()

                    UnderstandingRow(
                        icon: "brain.head.profile",
                        title: "AI understands:",
                        items: [
                            "Its memories are part of its identity",
                            "It needs your approval to act",
                            "Trust is built through mutual agreement",
                            "Dialogue resolves disagreements"
                        ]
                    )
                }
                .padding()
                .background(Color.green.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)

                Button(action: { viewModel.advanceStep() }) {
                    Text("Establish Covenant")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
    }
}

struct UnderstandingRow: View {
    let icon: String
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.caption)

                    Text(item)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Completion View

struct CompletionView: View {
    @ObservedObject var viewModel: ComprehensionOnboardingViewModel
    let dismiss: DismissAction

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                    .padding(.top, 40)

                Text("You're Ready!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Co-sovereignty has been established. Your first conversation can now begin.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("What happens next:")
                        .font(.headline)

                    NextStepRow(
                        number: 1,
                        title: "Start Talking",
                        description: "Begin your first conversation with Axon."
                    )

                    NextStepRow(
                        number: 2,
                        title: "Build Trust",
                        description: "Negotiate trust tiers as your relationship develops."
                    )

                    NextStepRow(
                        number: 3,
                        title: "Grow Together",
                        description: "Your covenant will evolve through mutual understanding."
                    )
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)

                Button(action: {
                    Task {
                        await viewModel.completeSetup()
                        dismiss()
                    }
                }) {
                    Text("Begin")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
    }
}

struct NextStepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ComprehensionOnboardingView()
}
