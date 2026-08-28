import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingAccountEntryView: View {
    let store: OpenLARPStore
    let continueLocally: () -> Void

    @State private var presentationAnchor: OpenLARPAuthenticationPresentationAnchor?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OpenLARPHeroCard(
                feature: .profile,
                eyebrow: "Your private workspace",
                title: "How should OpenLARP remember you?",
                subtitle: "Link an account for supported cloud restoration, or keep this sprint only on this iPhone. You can link later.",
                stat: "Optional"
            )

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Account-backed beta", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("Apple and Google sign-in identify your private account. They do not let OpenLARP send messages, submit applications, or publish anything.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task {
                            await store.signInWithApple(presenting: presentationAnchor)
                        }
                    } label: {
                        if store.isSigningInWithApple {
                            accountProgressLabel("Opening Apple")
                        } else {
                            Label("Continue with Apple", systemImage: "apple.logo")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(actionsAreDisabled)

                    Button {
                        Task {
                            await store.signInWithGoogle(presenting: presentationAnchor)
                        }
                    } label: {
                        if store.isSigningInWithGoogle {
                            accountProgressLabel("Opening Google")
                        } else {
                            Label("Continue with Google", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(actionsAreDisabled)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Use this iPhone only", systemImage: "iphone")
                        .font(.headline)
                    Text("Your career answers and proof stay in protected local app storage. They will not restore on another device unless you link and sync later.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: continueLocally) {
                        Label("Use This iPhone Only", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(actionsAreDisabled)
                }
            }

            if let message = store.authenticationResult?.message,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(message, systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.openLARPAttentionText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .background {
            authenticationPresentationAnchorReader
        }
    }

    private var actionsAreDisabled: Bool {
        store.isAuthenticationOperationInFlight || store.isAccountDataOperationInFlight
    }

    private func accountProgressLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
        }
    }

    @ViewBuilder
    private var authenticationPresentationAnchorReader: some View {
        #if canImport(UIKit)
        OnboardingAuthenticationPresentationAnchorReader { anchor in
            presentationAnchor = anchor
        }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(UIKit)
private struct OnboardingAuthenticationPresentationAnchorReader: UIViewControllerRepresentable {
    let onResolve: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        OnboardingAuthenticationAnchorViewController(onResolve: onResolve)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        onResolve(uiViewController)
    }
}

private final class OnboardingAuthenticationAnchorViewController: UIViewController {
    let onResolve: (UIViewController) -> Void

    init(onResolve: @escaping (UIViewController) -> Void) {
        self.onResolve = onResolve
        super.init(nibName: nil, bundle: nil)
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onResolve(self)
    }
}
#endif
