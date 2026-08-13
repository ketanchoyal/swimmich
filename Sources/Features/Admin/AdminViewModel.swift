import Foundation

/// Admin panel state (gap #12): users, jobs, libraries, API keys. Admin-gated
/// at the view level via `auth.isAdmin`; the VM is plain CRUD over the admin
/// endpoints.
@Observable
@MainActor
final class AdminViewModel {
    let client: any ImmichClient

    var users: [UserAdminResponseDto] = []
    var jobs: [String: QueueResponseLegacyDto] = [:]
    var libraries: [LibraryResponseDto] = []
    var apiKeys: [ApiKeyResponseDto] = []

    var isLoading = false
    var errorMessage: String?

    /// One-shot secret from the last API-key creation (shown once).
    var lastAPIKeySecret: String?

    init(client: any ImmichClient) {
        self.client = client
    }

    /// Sorted queue names so the jobs list is stable across refreshes.
    var sortedJobNames: [String] { jobs.keys.sorted() }

    func load(force: Bool = false) async {
        guard !(isLoading && !force) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let u = client.getAdminUsers()
            async let j = client.getJobsStatus()
            async let l = client.getLibraries()
            async let k = client.getAPIKeys()
            let (users, jobs, libraries, keys) = try await (u, j, l, k)
            self.users = users
            self.jobs = jobs
            self.libraries = libraries
            self.apiKeys = keys
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Users

    func createUser(name: String, email: String, password: String, isAdmin: Bool) async {
        let dto = UserAdminCreateDto(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            storageLabel: nil,
            quotaSizeInBytes: nil,
            shouldChangePassword: nil,
            isAdmin: isAdmin
        )
        do {
            _ = try await client.createAdminUser(dto: dto)
            errorMessage = nil
            await load(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteUser(_ user: UserAdminResponseDto, force: Bool) async {
        do {
            _ = try await client.deleteAdminUser(id: user.id, force: force)
            errorMessage = nil
            await load(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreUser(_ user: UserAdminResponseDto) async {
        do {
            _ = try await client.restoreAdminUser(id: user.id)
            errorMessage = nil
            await load(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Jobs

    func runJob(name: String, command: String) async {
        do {
            _ = try await client.sendJobCommand(name: name, command: command, force: command == "start" ? true : nil)
            errorMessage = nil
            await load(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Libraries

    func scanLibrary(_ library: LibraryResponseDto) async {
        do {
            try await client.scanLibrary(id: library.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteLibrary(_ library: LibraryResponseDto) async {
        do {
            try await client.deleteLibrary(id: library.id)
            errorMessage = nil
            await load(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - API keys

    func createAPIKey(name: String) async {
        do {
            let resp = try await client.createAPIKey(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            lastAPIKeySecret = resp.secret
            errorMessage = nil
            await load(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAPIKey(_ key: ApiKeyResponseDto) async {
        do {
            try await client.deleteAPIKey(id: key.id)
            errorMessage = nil
            await load(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
