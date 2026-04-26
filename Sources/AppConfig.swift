import Foundation

enum AppConfig {
    /// Loads secrets from Secrets.plist (local only, gitignored).
    private static let secretsDict: [String: Any]? = {
        let fileManager = FileManager.default
        
        // Denenecek yollar:
        let possiblePaths: [URL] = [
            // 1. Uygulamanın tam yanındaki Secrets.plist (en muhtemel yer)
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Secrets.plist"),
            
            // 2. Proje kök dizini (Geliştirme sırasında)
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Secrets.plist"),
                
            // 3. Mevcut çalışma dizini
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("Secrets.plist")
        ]
        
        for url in possiblePaths {
            if fileManager.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                #if DEBUG
                print("✅ Secrets.plist başarıyla yüklendi: \(url.path)")
                #endif
                return dict
            }
        }
        
        #if DEBUG
        print("⚠️ Secrets.plist hiçbir konumda bulunamadı!")
        #endif
        return nil
    }()
    
    static var googleOAuthClientID: String {
        // Öncelik 1: Secrets.plist
        if let id = secretsDict?["GoogleOAuthClientID"] as? String,
           !id.isEmpty, !id.contains("YOUR_") {
            return id
        }
        
        // Öncelik 2: Ortam Değişkeni
        if let env = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"],
           !env.isEmpty {
            return env
        }
        
        // Öncelik 3: Binary içine gömülü Info.plist (Genelde placeholder olur)
        if let id = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
           !id.isEmpty && !id.contains("YOUR_") {
            return id
        }
        
        #if DEBUG
        print("❌ HATA: Geçerli bir GoogleOAuthClientID bulunamadı!")
        #endif
        return ""
    }

    static var googleOAuthRedirectURI: String {
        if let u = secretsDict?["GoogleOAuthRedirectURI"] as? String { return u }
        return (Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthRedirectURI") as? String) ?? "http://localhost:8080"
    }

    static var googleOAuthClientSecret: String {
        if let s = secretsDict?["GoogleOAuthClientSecret"] as? String,
           !s.isEmpty, !s.contains("YOUR_") {
            return s
        }
        
        if let env = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_SECRET"],
           !env.isEmpty {
            return env
        }
        
        if let secret = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String,
           !secret.isEmpty && !secret.contains("YOUR_") {
            return secret
        }
        
        return ""
    }
}
