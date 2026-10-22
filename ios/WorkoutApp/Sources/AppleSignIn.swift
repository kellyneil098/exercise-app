import AuthenticationServices
import SwiftUI
import WorkoutUI

/// Sign in with Apple → `/auth/apple`. Requires the entitlement (paid team); until then the button
/// fails gracefully with an error message.
struct AppleSignInButton: View {
    let inviteCode: String?
    let onError: (String) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        SignInWithAppleButton(.signIn) { req in
            req.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                    onError("No identity token"); return
                }
                let name = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                Task {
                    do { try await model.appleLogin(identityToken: token, inviteCode: inviteCode, displayName: name.isEmpty ? nil : name) }
                    catch { onError("Sign in failed: \(error)") }
                }
            case .failure(let e): onError(e.localizedDescription)
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}
