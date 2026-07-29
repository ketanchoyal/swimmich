import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        @Bindable var auth = auth
        Form {
            Section("Credentials") {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                SecureField("Password", text: $password)
            }

            if let err = auth.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await auth.login(email: email, password: password) }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                    } else {
                        Text("Sign in")
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || auth.isLoading)
            }
        }
        .navigationTitle("Sign in")
    }
}
