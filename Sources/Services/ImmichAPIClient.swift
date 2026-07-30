import Foundation

/// Delegate notified on global 401 (FM-4) so AuthViewModel can reset auth state
/// without the client holding a back-reference (avoids circular dependency).
protocol AuthSessionDelegate: AnyObject, Sendable {
    func didReceiveUnauthorized()
}

/// URLSession-backed ImmichClient implementation.
///
/// Notes:
/// - Holds the bearer token + base URL set by the AuthViewModel.
/// - On 401 anywhere → throws `.unauthorized` AND notifies `authDelegate` (FM-4).
/// - `requestCount` increments on every network dispatch (AC-009).
final class ImmichAPIClient: ImmichClient, @unchecked Sendable {
    private let session: URLSession
    private let lock = NSLock()

    private var _token: String?
    private var _baseURL: URL?
    private var _requestCount: Int = 0

    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return _requestCount }

    weak var authDelegate: AuthSessionDelegate?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Configuration

    func configure(baseURL: URL?, token: String?) {
        lock.lock(); defer { lock.unlock() }
        _baseURL = baseURL
        _token = token
    }

    var baseURL: URL? { lock.lock(); defer { lock.unlock() }; return _baseURL }
    var token: String? { lock.lock(); defer { lock.unlock() }; return _token }

    private func bumpRequestCount() {
        lock.lock(); _requestCount += 1; lock.unlock()
    }

    // MARK: - Server

    func ping() async throws -> ServerPingResponse {
        try await sendNoAuth(.GET, path: ImmichAPI.server.path("/ping"))
    }

    func serverVersion() async throws -> ServerVersionResponseDto {
        try await sendNoAuth(.GET, path: ImmichAPI.server.path("/version"))
    }

    func serverConfig() async throws -> ServerConfigDto {
        try await sendNoAuth(.GET, path: ImmichAPI.server.path("/config"))
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> LoginResponseDto {
        try await sendNoAuth(.POST, path: ImmichAPI.auth.path("/login"), body: AnyEncodable(LoginCredentialDto(email: email, password: password)))
    }

    func logout() async throws -> LogoutResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.auth.path("/logout"))
    }

    func validateToken() async throws -> ValidateAccessTokenResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.auth.path("/validateToken"))
    }

    // MARK: - Timeline

    func getTimeBuckets(isFavorite: Bool?, isTrashed: Bool?) async throws -> [TimeBucketsResponseDto] {
        var query: [URLQueryItem] = []
        if let isFavorite { query.append(URLQueryItem(name: "isFavorite", value: String(isFavorite))) }
        if let isTrashed { query.append(URLQueryItem(name: "isTrashed", value: String(isTrashed))) }
        return try await sendAuthed(.GET, path: ImmichAPI.timeline.path("/buckets"), query: query)
    }

    func getTimeBucket(timeBucket: String) async throws -> TimeBucketAssetResponseDto {
        let query = [URLQueryItem(name: "timeBucket", value: timeBucket)]
        return try await sendAuthed(.GET, path: ImmichAPI.timeline.path("/bucket"), query: query)
    }

    // MARK: - Asset actions

    func getAsset(id: String) async throws -> AssetResponseDto {
        try await sendAuthed(.GET, path: ImmichAPI.assets.path("/\(id)"))
    }

    func updateAsset(id: String, dto: UpdateAssetDto) async throws -> AssetResponseDto {
        try await sendAuthed(.PATCH, path: ImmichAPI.assets.path("/\(id)"), body: AnyEncodable(dto))
    }

    func deleteAssets(ids: [String], force: Bool?) async throws {
        let body = AnyEncodable(AssetBulkDeleteDto(ids: ids, force: force))
        _ = try await sendAuthedRaw(.DELETE, path: ImmichAPI.assets.path(""), body: body)
    }

    // MARK: - Trash (AC-307..AC-309)

    func restoreTrashAssets(ids: [String]) async throws -> TrashResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.trash.path("/restore/assets"), body: AnyEncodable(BulkIdsDto(ids: ids)))
    }

    func restoreAllTrash() async throws -> TrashResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.trash.path("/restore"), body: nil)
    }

    func emptyTrash() async throws -> TrashResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.trash.path("/empty"), body: nil)
    }

    // MARK: - Search (AC-400..AC-406)

    func searchMetadata(dto: MetadataSearchDto) async throws -> SearchResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.search.path("/metadata"), body: AnyEncodable(dto))
    }

    func searchSmart(dto: SmartSearchDto) async throws -> SearchResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.search.path("/smart"), body: AnyEncodable(dto))
    }

    func getExploreData() async throws -> [SearchExploreResponseDto] {
        try await sendAuthed(.GET, path: ImmichAPI.search.path("/explore"))
    }

    // MARK: - Albums (AC-500..AC-518)

    func getAlbums() async throws -> [AlbumResponseDto] {
        try await sendAuthed(.GET, path: ImmichAPI.albums.path(""))
    }

    func createAlbum(dto: CreateAlbumDto) async throws -> AlbumResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.albums.path(""), body: AnyEncodable(dto))
    }

    func getAlbum(id: String) async throws -> AlbumResponseDto {
        try await sendAuthed(.GET, path: ImmichAPI.albums.path("/\(id)"))
    }

    func deleteAlbum(id: String) async throws {
        _ = try await sendAuthedRaw(.DELETE, path: ImmichAPI.albums.path("/\(id)"), body: nil)
    }

    func addAssetsToAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto] {
        try await sendAuthed(.PUT, path: ImmichAPI.albums.path("/\(albumId)/assets"), body: AnyEncodable(dto))
    }

    func removeAssetsFromAlbum(albumId: String, dto: BulkIdsDto) async throws -> [BulkIdResponseDto] {
        try await sendAuthed(.DELETE, path: ImmichAPI.albums.path("/\(albumId)/assets"), body: AnyEncodable(dto))
    }

    // MARK: - Shared Links (AC-500..AC-518)

    func getSharedLinks(albumId: String?) async throws -> [SharedLinkResponseDto] {
        var query: [URLQueryItem] = []
        if let albumId {
            query.append(URLQueryItem(name: "albumId", value: albumId))
        }
        return try await sendAuthed(.GET, path: ImmichAPI.sharedLinks.path(""), query: query)
    }

    func createSharedLink(dto: SharedLinkCreateDto) async throws -> SharedLinkResponseDto {
        try await sendAuthed(.POST, path: ImmichAPI.sharedLinks.path(""), body: AnyEncodable(dto))
    }

    func deleteSharedLink(id: String) async throws {
        _ = try await sendAuthedRaw(.DELETE, path: ImmichAPI.sharedLinks.path("/\(id)"), body: nil)
    }

    // MARK: - Upload

    func uploadAsset(
        data: Data,
        fileCreatedAt: String,
        fileModifiedAt: String,
        filename: String,
        duration: Int?,
        isFavorite: Bool,
        visibility: AssetVisibility,
        livePhotoVideoId: String?,
        checksum: String
    ) async throws -> AssetMediaResponseDto {
        guard let url = resolvedURL(path: ImmichAPI.assets.path("")) else { throw APIError.invalidURL }

        var multipart = MultipartBody()
        multipart.append(name: "assetData", filename: filename, contentType: "application/octet-stream", data: data)
        multipart.append(name: "fileCreatedAt", value: fileCreatedAt)
        multipart.append(name: "fileModifiedAt", value: fileModifiedAt)
        if let duration {
            multipart.append(name: "duration", value: String(duration))
        }
        multipart.append(name: "isFavorite", value: isFavorite ? "true" : "false")
        multipart.append(name: "visibility", value: visibility.rawValue)
        if let livePhotoVideoId {
            multipart.append(name: "livePhotoVideoId", value: livePhotoVideoId)
        }
        let body = multipart.encoded()

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.POST.rawValue
        request.setValue(MultipartBody.contentType(forBoundary: multipart.boundary), forHTTPHeaderField: ImmichHeader.contentType)
        request.setValue(ImmichAPI.acceptJSON, forHTTPHeaderField: ImmichHeader.accept)
        request.setValue(checksum, forHTTPHeaderField: ImmichHeader.checksum)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: ImmichHeader.authorization)
        }
        request.httpBody = body

        let (responseData, response) = try await dispatch(request)
        try validate(response: response, data: responseData)
        return try Self.decode(AssetMediaResponseDto.self, from: responseData)
    }

    func bulkUploadCheck(_ request: AssetBulkUploadCheckRequest) async throws -> AssetBulkUploadCheckResponse {
        try await sendAuthed(.POST, path: ImmichAPI.assets.path("/bulk-upload-check"), body: AnyEncodable(request))
    }

    // MARK: - Core dispatch

    private func sendNoAuth<T: Decodable>(_ method: HTTPMethod, path: String, body: AnyEncodable? = nil) async throws -> T {
        let data = try await sendRaw(method, path: path, auth: false, body: body)
        return try Self.decode(T.self, from: data)
    }

    private func sendAuthed<T: Decodable>(_ method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: AnyEncodable? = nil) async throws -> T {
        let data = try await sendAuthedRaw(method, path: path, query: query, body: body)
        return try Self.decode(T.self, from: data)
    }

    private func sendAuthedRaw(_ method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: AnyEncodable?) async throws -> Data {
        guard let token = token else { throw APIError.unauthorized }
        return try await sendRaw(method, path: path, query: query, auth: true, token: token, body: body)
    }

    private func sendRaw(_ method: HTTPMethod, path: String, query: [URLQueryItem] = [], auth: Bool, token: String? = nil, body: AnyEncodable?) async throws -> Data {
        guard let url = resolvedURL(path: path, query: query) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(ImmichAPI.acceptJSON, forHTTPHeaderField: ImmichHeader.accept)
        if auth, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: ImmichHeader.authorization)
        }
        if let body {
            let data = try JSONEncoder.immich.encode(body)
            request.setValue("application/json", forHTTPHeaderField: ImmichHeader.contentType)
            request.httpBody = data
        }
        let (responseData, response) = try await dispatch(request)
        try validate(response: response, data: responseData)
        return responseData
    }

    private func dispatch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        bumpRequestCount()
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        } catch {
            throw APIError.from(error)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            authDelegate?.didReceiveUnauthorized()
            throw APIError.unauthorized
        }
        if http.statusCode == 204 { return }
        if !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8)
            throw APIError.serverError(http.statusCode, message)
        }
    }

    private func resolvedURL(path: String, query: [URLQueryItem] = []) -> URL? {
        guard let base = baseURL else { return nil }
        let url = base.appendingPathComponent(path)
        guard !query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = query
        return components?.url
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.immich.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

enum HTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}
