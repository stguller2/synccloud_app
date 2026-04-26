import AppKit
import CryptoKit
import Darwin
import Foundation
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
                // Save refresh token if present
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
    
    /// Refresh the access token using stored refresh token — no user interaction needed
    static func refreshAccessToken(completion: @escaping (String?) -> Void) {
        guard let refreshToken = KeychainTokenStore.readRefreshToken(), !refreshToken.isEmpty else {
            #if DEBUG
            print("⚠️ Refresh token Keychain'de bulunamadı.")
            #endif
            completion(nil)
            return
        }
        
        #if DEBUG
        print("🔑 Refresh token bulundu, yenileme isteği gönderiliyor...")
        #endif
        
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
            if let error = error {
                #if DEBUG
                print("❌ Refresh ağ hatası: \(error.localizedDescription)")
                #endif
                completion(nil)
                return
            }
            
            let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("❌ Refresh yanıtı parse edilemedi (HTTP \(httpCode))")
                #endif
                completion(nil)
                return
            }
            
            if let newToken = json["access_token"] as? String, !newToken.isEmpty {
                KeychainTokenStore.save(newToken)
                #if DEBUG
                print("✅ Token otomatik yenilendi! (HTTP \(httpCode))")
                #endif
                completion(newToken)
            } else {
                #if DEBUG
                let err = json["error"] as? String ?? "unknown"
                let desc = json["error_description"] as? String ?? ""
                print("❌ Refresh başarısız: \(err) — \(desc) (HTTP \(httpCode))")
                #endif
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

final class LocalHTTPServer {
    private let port: UInt16
    private let onReady: () -> Void
    private let onCode: (String) -> Void
    private let onBindFailed: () -> Void
    private var isRunning = false
    private var serverSocket: Int32 = -1
    private var bindFailedReported = false

    init(port: UInt16, onReady: @escaping () -> Void, onCode: @escaping (String) -> Void, onBindFailed: @escaping () -> Void) {
        self.port = port
        self.onReady = onReady
        self.onCode = onCode
        self.onBindFailed = onBindFailed
    }

    func start() {
        isRunning = true
        bindFailedReported = false
        Thread.detachNewThread {
            self.runServer()
        }
    }

    func stop() {
        isRunning = false
        if serverSocket != -1 {
            // Shutdown first to unblock accept(), then close
            Darwin.shutdown(serverSocket, SHUT_RDWR)
            close(serverSocket)
            serverSocket = -1
        }
    }

    private func reportBindFailedOnce() {
        if bindFailedReported { return }
        bindFailedReported = true
        onBindFailed()
    }

    private func runServer() {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            reportBindFailedOnce()
            return
        }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout.size(ofValue: opt)))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult < 0 {
            #if DEBUG
            print("Sunucu başlatılamadı: Port \(port) kullanımda olabilir.")
            #endif
            reportBindFailedOnce()
            if serverSocket != -1 {
                close(serverSocket)
                serverSocket = -1
            }
            return
        }

        listen(serverSocket, 1)
        #if DEBUG
        print("Yerel dogrulama sunucusu dinliyor (Port \(port))...")
        #endif
        DispatchQueue.main.async {
            self.onReady()
        }

        while isRunning {
            let clientSock = accept(serverSocket, nil, nil)
            guard clientSock >= 0 else {
                // accept failed — likely socket was shut down via stop()
                break
            }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytes = recv(clientSock, &buffer, buffer.count - 1, 0)

            if bytes > 0 {
                let request = String(bytes: buffer.prefix(bytes), encoding: .utf8) ?? ""
                if let range = request.range(of: "code="),
                   let endRange = request.range(of: " HTTP", range: range.upperBound..<request.endIndex) {
                    let fullCode = String(request[range.upperBound..<endRange.lowerBound])
                    let code = fullCode.components(separatedBy: "&").first ?? ""

                    let response = """
                    HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n
                    <html><body style='font-family:-apple-system,sans-serif;text-align:center;padding:50px;background:#f5f5f7'>
                    <h1 style='color:#007aff'>✅ İşlem Başarılı!</h1>
                    <p style='color:#1d1d1f'>Giriş yapıldı. SyncCloud uygulamasına dönebilirsiniz.</p>
                    <p style='color:#86868b;font-size:12px'>Bu pencereyi kapatabilirsiniz.</p>
                    </body></html>
                    """
                    send(clientSock, response, response.utf8.count, 0)
                    close(clientSock)
                    onCode(code)
                    break
                }
            }
            close(clientSock)
        }
        stop()
    }
}
