import Foundation

final class GoogleDriveService {
    private let uploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
    private let searchEndpoint = "https://www.googleapis.com/drive/v3/files"
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static func driveQueryEscapedFileName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "heic": return "image/heic"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }

    func getFileInfo(name: String, accessToken: String, completion: @escaping ((id: String, size: Int64)?) -> Void) {
        let safeName = Self.driveQueryEscapedFileName(name)
        var components = URLComponents(string: searchEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(safeName)' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id, name, size)")
        ]

        guard let url = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        self.session.dataTask(with: request) { data, _, error in
            if let error = error {
                #if DEBUG
                print("getFileInfo network error: \(error.localizedDescription)")
                #endif
                completion(nil)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let files = json["files"] as? [[String: Any]],
                  let firstFile = files.first else {
                completion(nil)
                return
            }
            let sizeStr = firstFile["size"] as? String ?? "0"
            let id = firstFile["id"] as? String ?? ""
            completion((id: id, size: Int64(sizeStr) ?? 0))
        }.resume()
    }

    func listFiles(accessToken: String, completion: @escaping ([(id: String, name: String, size: Int64)]) -> Void) {
        var allFiles: [(id: String, name: String, size: Int64)] = []
        let group = DispatchGroup()
        
        func fetchPage(token: String?) {
            var components = URLComponents(string: searchEndpoint)!
            var queryItems = [
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "fields", value: "files(id, name, size), nextPageToken"),
                URLQueryItem(name: "q", value: "trashed = false")
            ]
            if let token = token {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            components.queryItems = queryItems
            
            guard let url = components.url else { completion(allFiles); return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            group.enter()
            self.session.dataTask(with: request) { data, _, error in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let files = json["files"] as? [[String: Any]] else { return }
                
                for f in files {
                    if let id = f["id"] as? String, let name = f["name"] as? String {
                        let size = Int64(f["size"] as? String ?? "0") ?? 0
                        allFiles.append((id: id, name: name, size: size))
                    }
                }
                
                if let nextToken = json["nextPageToken"] as? String {
                    fetchPage(token: nextToken)
                }
            }.resume()
        }
        
        fetchPage(token: nil)
        group.notify(queue: .main) {
            completion(allFiles)
        }
    }
    
    func deleteFile(id: String, accessToken: String, completion: @escaping () -> Void) {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        self.session.dataTask(with: request) { _, _, _ in
            completion()
        }.resume()
    }

    func uploadPhoto(name: String, data: Data, accessToken: String, forceReplaceId: String? = nil, skipDuplicateCheck: Bool = false, completion: @escaping (Bool, String?) -> Void) {
        if let id = forceReplaceId {
            self.deleteFile(id: id, accessToken: accessToken) {
                self.performUpload(name: name, data: data, accessToken: accessToken, completion: completion)
            }
        } else if skipDuplicateCheck {
            // Direct upload — no duplicate check (used by diff upload where we already know the state)
            self.performUpload(name: name, data: data, accessToken: accessToken, completion: completion)
        } else {
            getFileInfo(name: name, accessToken: accessToken) { fileInfo in
                if fileInfo != nil {
                    #if DEBUG
                    print("Dosya zaten var: \(name)")
                    #endif
                    completion(true, nil)
                    return
                }
                self.performUpload(name: name, data: data, accessToken: accessToken, completion: completion)
            }
        }
    }

    private func performUpload(name: String, data: Data, accessToken: String, completion: @escaping (Bool, String?) -> Void) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: uploadEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var httpBody = Data()
        httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
        httpBody.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        let metadata: [String: Any] = ["name": name]
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata, options: []) else {
            completion(false, "Dosya bilgisi hazırlanamadı")
            return
        }
        httpBody.append(metadataData)
        httpBody.append("\r\n".data(using: .utf8)!)

        httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
        let mime = self.mimeType(for: name)
        httpBody.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        httpBody.append(data)
        httpBody.append("\r\n".data(using: .utf8)!)

        httpBody.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = httpBody

        self.session.dataTask(with: request) { data, response, error in
            if let error = error {
                #if DEBUG
                print("Upload network error: \(error.localizedDescription)")
                #endif
                completion(false, "Bağlantı hatası: \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            if code != 200 && code != 201 {
                if code == 401 {
                    completion(false, "Oturum süresi doldu (401)")
                    return
                } else if code == 403 {
                    completion(false, "Google Drive doldu veya yetkisiz (403)")
                    return
                } else {
                    completion(false, "Google API Hatası (Kod: \(code))")
                    return
                }
            }
            completion(true, nil)
        }.resume()
    }
}
