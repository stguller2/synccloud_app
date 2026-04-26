import Foundation
import Photos
import Combine
import AppKit

/// Background auto-sync engine that monitors iCloud photo library
/// and uploads new photos to Google Drive at configurable intervals
final class BackgroundSyncEngine: ObservableObject {
    
    enum SyncInterval: Int, CaseIterable {
        case realtime = 0
        case every15min = 15
        case every30min = 30
        case everyHour = 60
        case every6Hours = 360
        
        var label: String {
            switch self {
            case .realtime:    return "Gerçek Zamanlı"
            case .every15min:  return "Her 15 dk"
            case .every30min:  return "Her 30 dk"
            case .everyHour:   return "Her Saat"
            case .every6Hours: return "Her 6 Saat"
            }
        }
    }
    
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "bgSyncEnabled")
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    
    @Published var syncInterval: SyncInterval = .everyHour {
        didSet {
            UserDefaults.standard.set(syncInterval.rawValue, forKey: "bgSyncInterval")
            if isEnabled { restartTimer() }
        }
    }
    
    @Published var lastSyncDate: Date? = nil
    @Published var lastSyncCount: Int = 0
    @Published var isBackgroundSyncing: Bool = false
    @Published var statusMessage: String = "Beklemede"
    
    private var syncTimer: Timer?
    private var currentObserver: PhotoLibraryObserver?
    private var lastKnownPhotoCount: Int = 0
    private let syncQueue = DispatchQueue(label: "com.synccloud.background", qos: .utility)
    private let googleDrive = GoogleDriveService()
    
    // Track which files we've already uploaded (persisted with size limit)
    private static let maxTrackedFiles = 5000
    
    private var uploadedFileNames: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "bgUploadedFiles") ?? [])
        }
        set {
            // Prevent unbounded growth — keep only the most recent entries
            var trimmed = newValue
            if trimmed.count > Self.maxTrackedFiles {
                let excess = trimmed.count - Self.maxTrackedFiles
                for _ in 0..<excess {
                    trimmed.remove(trimmed.first!)
                }
            }
            UserDefaults.standard.set(Array(trimmed), forKey: "bgUploadedFiles")
        }
    }
    
    weak var syncManager: SyncManager?
    
    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "bgSyncEnabled")
        let savedInterval = UserDefaults.standard.integer(forKey: "bgSyncInterval")
        syncInterval = SyncInterval(rawValue: savedInterval) ?? .everyHour
        
        if let lastDate = UserDefaults.standard.object(forKey: "bgLastSyncDate") as? Date {
            lastSyncDate = lastDate
        }
        lastSyncCount = UserDefaults.standard.integer(forKey: "bgLastSyncCount")
        
        // Snapshot current photo count
        let allPhotos = PHAsset.fetchAssets(with: .image, options: nil)
        lastKnownPhotoCount = allPhotos.count
        
        if isEnabled { startMonitoring() }
    }
    
    deinit {
        // Fix #12: Unregister observer on cleanup
        if let observer = currentObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        }
        syncTimer?.invalidate()
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard isEnabled else { return }
        
        statusMessage = "Arka plan izleme aktif"
        syncManager?.addLog("🔄 Arka plan senkronizasyonu başlatıldı (\(syncInterval.label))")
        
        if syncInterval == .realtime {
            // Register for photo library change notifications
            let observer = PhotoLibraryObserver(engine: self)
            PHPhotoLibrary.shared().register(observer)
            currentObserver = observer
            statusMessage = "Gerçek zamanlı izleniyor"
        }
        
        restartTimer()
    }
    
    func stopMonitoring() {
        syncTimer?.invalidate()
        syncTimer = nil
        
        // Unregister observer
        if let observer = currentObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
            currentObserver = nil
        }
        
        statusMessage = "Durduruldu"
        syncManager?.addLog("⏹ Arka plan senkronizasyonu durduruldu.")
    }
    
    private func restartTimer() {
        syncTimer?.invalidate()
        
        guard syncInterval != .realtime else {
            // Realtime mode uses observer, but also check every 5 mins as fallback
            syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                self?.checkForNewPhotos()
            }
            return
        }
        
        let interval = TimeInterval(syncInterval.rawValue * 60)
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForNewPhotos()
        }
    }
    
    // MARK: - Photo Check & Upload
    
    func checkForNewPhotos() {
        guard !isBackgroundSyncing else { return }
        guard let token = KeychainTokenStore.read(), !token.isEmpty else {
            statusMessage = "Google oturumu gerekli"
            return
        }
        
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isBackgroundSyncing = true
                self.statusMessage = "Yeni fotoğraflar kontrol ediliyor..."
            }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            let total = allPhotos.count
            
            // Find files not yet uploaded
            var newResources: [(resource: PHAssetResource, asset: PHAsset, name: String, size: Int64)] = []
            let knownFiles = self.uploadedFileNames
            
            for i in 0..<total {
                let asset = allPhotos.object(at: i)
                let resources = PHAssetResource.assetResources(for: asset)
                
                for resource in resources {
                    // Sync photo and paired video
                    guard resource.type == .photo || resource.type == .pairedVideo || resource.type == .video || resource.type == .fullSizePhoto else { continue }
                    
                    let fileName = resource.originalFilename
                    if !knownFiles.contains(fileName) {
                        let size = Int64(resource.value(forKey: "fileSize") as? Int ?? 0)
                        newResources.append((resource, asset, fileName, size))
                    }
                }
                
                // Track assets checked (limit to 50 recent assets for performance, which could be ~100 resources)
                if i >= 50 { break }
            }
            
            guard !newResources.isEmpty else {
                DispatchQueue.main.async {
                    self.isBackgroundSyncing = false
                    self.statusMessage = "Güncel — yeni dosya yok"
                    self.lastSyncDate = Date()
                    UserDefaults.standard.set(Date(), forKey: "bgLastSyncDate")
                }
                self.syncManager?.addLog("✅ Arka plan: Yeni fotoğraf yok, her şey güncel.")
                return
            }
            
            self.syncManager?.addLog("📸 Arka plan: \(newResources.count) yeni dosya/video bulundu, yükleniyor...")
            DispatchQueue.main.async {
                self.statusMessage = "\(newResources.count) dosya yükleniyor..."
            }
            
            var uploadedCount = 0
            var currentToken = token
            
            for (index, item) in newResources.enumerated() {
                let sema = DispatchSemaphore(value: 0)
                
                // Export asset data
                var assetData = Data()
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                
                let resources = PHAssetResource.assetResources(for: item.asset)
                guard !resources.isEmpty else {
                    sema.signal()
                    continue
                }
                
                PHAssetResourceManager.default().requestData(for: item.resource, options: options, dataReceivedHandler: { part in
                    assetData.append(part)
                }) { error in
                    guard !assetData.isEmpty else {
                        sema.signal()
                        return
                    }
                    
                    self.googleDrive.uploadPhoto(name: item.name, data: assetData, accessToken: currentToken, skipDuplicateCheck: true) { success, errMsg in
                        if success {
                            uploadedCount += 1
                            var known = self.uploadedFileNames
                            known.insert(item.name)
                            self.uploadedFileNames = known
                            
                            self.syncManager?.addLog("✅ Arka plan [\(index+1)/\(newResources.count)]: \(item.name)")
                            sema.signal()
                        } else {
                            let reason = errMsg ?? "Bilinmeyen"
                            
                            // Fix #4: Auto-refresh token on 401
                            if reason.contains("401") {
                                self.syncManager?.addLog("🔄 Arka plan: Token yenileniyor...")
                                GoogleAuthManager.refreshAccessToken { newToken in
                                    if let newToken = newToken {
                                        currentToken = newToken
                                        // Retry with new token
                                        self.googleDrive.uploadPhoto(name: item.name, data: assetData, accessToken: newToken, skipDuplicateCheck: true) { retryOk, _ in
                                            if retryOk {
                                                uploadedCount += 1
                                                var known = self.uploadedFileNames
                                                known.insert(item.name)
                                                self.uploadedFileNames = known
                                                self.syncManager?.addLog("✅ Arka plan [\(index+1)/\(newResources.count)]: \(item.name)")
                                            } else {
                                                self.syncManager?.addLog("❌ Arka plan yeniden deneme başarısız: \(item.name)")
                                            }
                                            sema.signal()
                                        }
                                    } else {
                                        self.syncManager?.addLog("🛑 Token yenilenemedi. Lütfen yeniden giriş yapın.")
                                        sema.signal()
                                    }
                                }
                            } else {
                                self.syncManager?.addLog("❌ Arka plan hata (\(reason)): \(item.name)")
                                sema.signal()
                            }
                        }
                    }
                }
                sema.wait()
            }
            
            DispatchQueue.main.async {
                self.isBackgroundSyncing = false
                self.lastSyncDate = Date()
                self.lastSyncCount = uploadedCount
                self.statusMessage = "\(uploadedCount) dosya yüklendi"
                
                UserDefaults.standard.set(Date(), forKey: "bgLastSyncDate")
                UserDefaults.standard.set(uploadedCount, forKey: "bgLastSyncCount")
            }
            
            self.syncManager?.addLog("🏁 Arka plan tamamlandı: \(uploadedCount)/\(newResources.count) yüklendi.")
        }
    }
    
    // Called by PHPhotoLibraryChangeObserver for realtime mode
    func photoLibraryDidChange() {
        guard isEnabled && syncInterval == .realtime else { return }
        
        // Small delay to let the system settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.checkForNewPhotos()
        }
    }
}

// MARK: - Photo Library Observer (Realtime)
private class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    weak var engine: BackgroundSyncEngine?
    
    init(engine: BackgroundSyncEngine) {
        self.engine = engine
        super.init()
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        engine?.photoLibraryDidChange()
    }
}
