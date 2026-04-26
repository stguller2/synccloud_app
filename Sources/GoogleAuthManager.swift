import AppKit
import CryptoKit
import Foundation
import Network
import Security

final class GoogleAuthManager: ObservableObject {
    private let clientID = AppConfig.googleOAuthClientID
    private let clientSecret = AppConfig.googleOAuthClientSecret
    private let redirectURI = AppConfig.googleOAuthRedirectURI
    private let scope = "https://www.googleapis.com/auth/drive.file"

    private var localServer: LocalHTTPServer?

    func signIn(completion: @escaping (GoogleLoginResult) -> Void) {
        guard !clientID.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure("GoogleOAuthClientID tanımlı değil (Info.plist)."))
            }
            return
        }

        localServer?.stop()

        let verifier = Self.newCodeVerifier()
        let challenge = Self.codeChallengeS256(verifier: verifier)

        localServer = LocalHTTPServer(
            port: 8080,
            onReady: { [weak self] in
                guard let self = self else { return }
                guard let url = self.buildAuthURL(codeChallenge: challenge) else {
                    completion(GoogleLoginResult.failure("Yetkilendirme adresi oluşturulamadı."))
                    return
                }
                #if DEBUG
                print("Giriş için tarayıcı açılıyor.")
                #endif
                NSWorkspace.shared.open(url)
            },
            onCode: { [weak self] code in
                self?.exchangeCodeForToken(code: code, codeVerifier: verifier) { result in
                    DispatchQueue.main.async {
                        completion(result)
                    }
                }
            },
            onBindFailed: {
                DispatchQueue.main.async {
                    completion(.failure("Yerel doğrulama sunucusu başlamadı. Port 8080 başka bir uygulama tarafından kullanılıyor olabilir."))
                }
            }
        )

        localServer?.start()
    }

    private func buildAuthURL(codeChallenge: String) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String, completion: @escaping (GoogleLoginResult) -> Void) {
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let body = Self.formURLEncodedBody([
            ("code", code),
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", codeVerifier)
        ]) else {
            completion(.failure("İstek gövdesi oluşturulamadı."))
            return
        }
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error.localizedDescription))
                return
            }
            guard let data = data else {
                completion(.failure("Sunucudan yanıt alınamadı."))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure("Geçersiz sunucu yanıtı."))
                return
            }
            if let token = json["access_token"] as? String, !token.isEmpty {
                if let refreshToken = json["refresh_token"] as? String, !refreshToken.isEmpty {
                    KeychainTokenStore.saveRefreshToken(refreshToken)
                    #if DEBUG
                    print("Refresh token kaydedildi.")
                    #endif
                }
                completion(.success(token))
                return
            }
            let err = (json["error"] as? String) ?? "unknown_error"
            let desc = (json["error_description"] as? String) ?? ""
            let message = desc.isEmpty ? err : "\(err): \(desc)"
            #if DEBUG
            print("Token yanıtı: \(message)")
            #endif
            completion(.failure(message))
        }.resume()
    }
    
    static func refreshAccessToken(completion: @escaping (String?) -> Void) {
        guard let refreshToken = KeychainTokenStore.readRefreshToken(), !refreshToken.isEmpty else {
            completion(nil)
            return
        }
        
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let clientID = AppConfig.googleOAuthClientID
        let clientSecret = AppConfig.googleOAuthClientSecret
        
        guard let body = formURLEncodedBody([
            ("refresh_token", refreshToken),
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("grant_type", "refresh_token")
        ]) else {
            completion(nil)
            return
        }
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let _ = error {
                completion(nil)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            
            if let newToken = json["access_token"] as? String, !newToken.isEmpty {
                KeychainTokenStore.save(newToken)
                completion(newToken)
            } else {
                completion(nil)
            }
        }.resume()
    }

    private static func newCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallengeS256(verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formURLEncodedBody(_ pairs: [(String, String)]) -> Data? {
        func enc(_ s: String) -> String {
            s.utf8.map { b -> String in
                switch b {
                case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                     UInt8(ascii: "a")...UInt8(ascii: "z"),
                     UInt8(ascii: "0")...UInt8(ascii: "9"),
                     UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
                    return String(UnicodeScalar(b))
                default:
                    return String(format: "%%%02X", b)
                }
            }.joined()
        }
        let body = pairs.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
        return Data(body.utf8)
    }
}

// Madde 3: Modern Network framework (NWListener) tabanlı sunucu
final class LocalHTTPServer {
    private let port: UInt16
    private let onReady: () -> Void
    private let onCode: (String) -> Void
    private let onBindFailed: () -> Void
    private var listener: NWListener?

    init(port: UInt16, onReady: @escaping () -> Void, onCode: @escaping (String) -> Void, onBindFailed: @escaping () -> Void) {
        self.port = port
        self.onReady = onReady
        self.onCode = onCode
        self.onBindFailed = onBindFailed
    }

    func start() {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async { self?.onReady() }
                case .failed(let error):
                    #if DEBUG
                    print("NWListener failed: \(error)")
                    #endif
                    DispatchQueue.main.async { self?.onBindFailed() }
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global())
        } catch {
            onBindFailed()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let data = data, let request = String(data: data, encoding: .utf8) {
                if let range = request.range(of: "code="),
                   let endRange = request.range(of: " HTTP", range: range.upperBound..<request.endIndex) {
                    let fullCode = String(request[range.upperBound..<endRange.lowerBound])
                    let code = fullCode.components(separatedBy: "&").first ?? ""
                    
                    let response = """
                    HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n
                    <html><body style='font-family:-apple-system,sans-serif;text-align:center;padding:50px;background:#f5f5f7'>
                    <h1 style='color:#007aff'>✅ İşlem Başarılı!</h1>
                    <p style='color:#1d1d1f'>Giriş yapıldı. SyncCloud uygulamasına dönebilirsiniz.</p>
                    <p style='color:#86868b;font-size:12px'>Bu pencereyi kapatabilirsiniz.</p>
                    </body></html>
                    """
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                    self?.onCode(code)
                    self?.stop()
                    return
                }
            }
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }
}
