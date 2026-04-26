import Foundation
import Photos
import SwiftUI

final class SyncManager: ObservableObject {
    @Published var photoLibraryStatus: PHAuthorizationStatus = .notDetermined
    @Published var totalPhotoCount: Int = 0
    @Published var isPermissionGranted: Bool = false
    @Published var syncStatus: String = "Hazır"
    @Published var syncLogs: [String] = []
    @Published var isGoogleConnected: Bool = false
    @Published var pendingDeleteCount: Int = 0
    @Published var needsDeleteConfirmation: Bool = false
    @Published var googleDriveFileCount: Int = 0
    @Published var googleDriveTotalSize: Int64 = 0
    @Published var isVerified: Bool = false
    @Published var isVerifying: Bool = false
    @Published var needsRepair: Bool = false
    @Published var uploadedFileCount: Int = 0
    @Published var diffItems: [DiffItem] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var isDiffUploading: Bool = false
    @Published var diffUploadStatus: String = ""
    
    var syncFilter = SyncFilter()
    let googleDrive = GoogleDriveService()
    var googleAccessToken: String = ""
    
    private let syncQueue = DispatchQueue(label: "com.synccloud.syncqueue", qos: .userInitiated)
    private var syncShouldCancel = false
    private var verifyShouldCancel = false
    private var scanShouldCancel = false
    private var diffUploadShouldCancel = false
    private var repairAssets: [(asset: PHAsset, driveId: String?)] = []
    private var currentSyncIndex: Int = 0
    private var globalUploadedFiles = Set<String>()
    
    init() { checkPermission() }
    
    func addLog(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.syncLogs.insert("[\(timestamp)] \(message)", at: 0)
            if self.syncLogs.count > 100 { self.syncLogs.removeLast() }
            self.syncStatus = message
        }
    }
    
    func checkPermission() {
        photoLibraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        isPermissionGranted = (photoLibraryStatus == .authorized || photoLibraryStatus == .limited)
        if isPermissionGranted { fetchPhotoCount() }
    }
    
    func requestPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.photoLibraryStatus = status
                self.isPermissionGranted = (status == .authorized || status == .limited)
                if self.isPermissionGranted { self.fetchPhotoCount() }
            }
        }
    }
    
    private func fetchPhotoCount() {
        let p = PHAsset.fetchAssets(with: .image, options: nil).count
        let v = PHAsset.fetchAssets(with: .video, options: nil).count
        DispatchQueue.main.async { self.totalPhotoCount = p + v }
    }

    func fetchGoogleDriveInfo(completion: @escaping (Int, Int64, [String: Int64]) -> Void) {
        guard !googleAccessToken.isEmpty else { completion(0, 0, [:]); return }
        googleDrive.listFiles(accessToken: googleAccessToken) { files in
            let count = files.count
            let totalSize = files.reduce(0) { $0 + $1.size }
            let sizeMap = Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.size) })
            completion(count, totalSize, sizeMap)
        }
    }

    func confirmDelete() {
        // Implementation for confirmed deletion
        addLog("🗑️ Silme işlemi onaylandı.")
    }

    func cancelDelete() {
        needsDeleteConfirmation = false
        repairAssets = []
        addLog("🚫 Silme işlemi iptal edildi.")
    }

    func exportResourceData(resource: PHAssetResource, completion: @escaping (Data?, String, Int64) -> Void) {
        let opt = PHAssetResourceRequestOptions()
        opt.isNetworkAccessAllowed = true
        let name = resource.originalFilename
        let size = Int64(resource.value(forKey: "fileSize") as? Int ?? 0)
        var buffer = Data()
        PHAssetResourceManager.default().requestData(for: resource, options: opt, dataReceivedHandler: { buffer.append($0) }, completionHandler: { error in
            if let error = error {
                self.addLog("⚠️ Veri çekme hatası (\(name)): \(error.localizedDescription)")
                if (error as NSError).code == 4099 {
                    self.addLog("🔥 Sistem servis bağlantısı koptu (photolibraryd).")
                }
            }
            completion(error == nil ? buffer : nil, name, size)
        })
    }

    func syncableResources(for asset: PHAsset) -> [PHAssetResource] {
        return PHAssetResource.assetResources(for: asset).filter { 
            [.photo, .video, .pairedVideo, .fullSizePhoto, .fullSizeVideo].contains($0.type)
        }
    }

    func startSync(progressCallback: @escaping (Double) -> Void, finished: @escaping () -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            self.syncShouldCancel = false
            let opt = PHFetchOptions()
            let assets = [PHAsset.fetchAssets(with: .image, options: opt), PHAsset.fetchAssets(with: .video, options: opt)]
            var all: [PHAsset] = []
            for r in assets { for j in 0..<r.count { all.append(r.object(at: j)) } }
            if all.isEmpty { DispatchQueue.main.async { finished() }; return }

            var consecutiveFailures = 0
            for i in self.currentSyncIndex..<all.count {
                autoreleasepool {
                    if self.syncShouldCancel { return }
                    self.currentSyncIndex = i
                    
                    for res in self.syncableResources(for: all[i]) {
                        if self.syncShouldCancel { break }
                        let sema = DispatchSemaphore(value: 0)
                        self.exportResourceData(resource: res) { data, name, _ in
                            guard let data = data else {
                                consecutiveFailures += 1
                                if consecutiveFailures > 5 {
                                    self.addLog("🚨 Üst üste çok fazla hata! Senkronizasyon güvenlik için durduruldu.")
                                    self.syncShouldCancel = true
                                }
                                Thread.sleep(forTimeInterval: 1.0)
                                sema.signal()
                                return
                            }
                            
                            consecutiveFailures = 0
                            self.googleDrive.uploadPhoto(name: name, data: data, accessToken: self.googleAccessToken) { ok, msg in
                                if ok { self.addLog("✅ Yüklendi: \(name)") }
                                else if (msg ?? "").contains("401") {
                                    GoogleAuthManager.refreshAccessToken { nt in
                                        if let t = nt {
                                            self.googleAccessToken = t
                                            self.googleDrive.uploadPhoto(name: name, data: data, accessToken: t) { r, _ in sema.signal() }
                                        } else { 
                                            self.addLog("🔑 Oturum yenilenemedi, lütfen tekrar giriş yapın.")
                                            self.syncShouldCancel = true
                                            sema.signal() 
                                        }
                                    }
                                    return
                                } else { self.addLog("❌ Hata: \(name)"); if (msg ?? "").contains("403") { self.syncShouldCancel = true } }
                                sema.signal()
                            }
                        }
                        sema.wait()
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
                DispatchQueue.main.async { progressCallback(Double(i+1)/Double(all.count)) }
            }
            DispatchQueue.main.async { finished() }
        }
    }

    func cancelSync() { syncShouldCancel = true; addLog("🛑 Durduruldu") }

    func verifySync() {
        verifyShouldCancel = false
        DispatchQueue.main.async { self.isVerifying = true }
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            let all = PHAsset.fetchAssets(with: .image, options: nil)
            self.repairAssets = []
            for i in 0..<all.count {
                if self.verifyShouldCancel { break }
                for res in self.syncableResources(for: all.object(at: i)) {
                    let sema = DispatchSemaphore(value: 0)
                    self.googleDrive.getFileInfo(name: res.originalFilename, accessToken: self.googleAccessToken) { info in
                        if let info = info {
                            let lSize = Int64(res.value(forKey: "fileSize") as? Int ?? 0)
                            if info.size != lSize { self.repairAssets.append((asset: all.object(at: i), driveId: info.id)) }
                        } else { self.repairAssets.append((asset: all.object(at: i), driveId: nil)) }
                        sema.signal()
                    }
                    sema.wait()
                }
            }
            DispatchQueue.main.async { self.isVerified = self.repairAssets.isEmpty; self.needsRepair = !self.repairAssets.isEmpty; self.isVerifying = false }
        }
    }

    func cancelVerify() { verifyShouldCancel = true; addLog("🛑 Durduruldu") }

    func repairIssues() {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            for item in self.repairAssets {
                for res in self.syncableResources(for: item.asset) {
                    let sema = DispatchSemaphore(value: 0)
                    self.exportResourceData(resource: res) { data, name, _ in
                        if let data = data {
                            self.googleDrive.uploadPhoto(name: name, data: data, accessToken: self.googleAccessToken, forceReplaceId: item.driveId) { _, _ in sema.signal() }
                        } else { sema.signal() }
                    }
                    sema.wait()
                }
            }
            DispatchQueue.main.async { self.needsRepair = false; self.repairAssets = [] }
        }
    }

    func cancelScan() { scanShouldCancel = true; addLog("🛑 Tarama durduruldu.") }
    func cancelDiffUpload() { diffUploadShouldCancel = true }

    func uploadDiffIssues() {
        let issues = diffItems.filter { $0.status == .missingCloud || $0.status == .sizeMismatch }
        guard !issues.isEmpty else { return }
        diffUploadShouldCancel = false
        DispatchQueue.main.async { self.isDiffUploading = true; self.diffUploadStatus = "0/\(issues.count)" }
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            for (i, item) in issues.enumerated() {
                if self.diffUploadShouldCancel { break }
                guard let asset = item.asset else { continue }
                let resources = self.syncableResources(for: asset)
                let res = resources.first(where: { $0.originalFilename == item.fileName }) ?? resources.first!
                let sema = DispatchSemaphore(value: 0)
                self.exportResourceData(resource: res) { data, name, _ in
                    if let data = data {
                        self.googleDrive.uploadPhoto(name: name, data: data, accessToken: self.googleAccessToken, forceReplaceId: item.driveId) { _, _ in sema.signal() }
                    } else { sema.signal() }
                }
                sema.wait()
                DispatchQueue.main.async { self.diffUploadStatus = "\(i+1)/\(issues.count)" }
            }
            DispatchQueue.main.async { self.isDiffUploading = false }
        }
    }

    func scanDiff() {
        scanShouldCancel = false
        DispatchQueue.main.async { self.isScanning = true; self.diffItems = [] }
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            var driveMap: [String: (id: String, size: Int64)] = [:]
            let sema = DispatchSemaphore(value: 0)
            self.fetchGoogleDriveInfoFull { files in
                for f in files { driveMap[f.name] = (id: f.id, size: f.size) }
                sema.signal()
            }
            sema.wait()
            let all = PHAsset.fetchAssets(with: .image, options: nil)
            var results: [DiffItem] = []
            var matched = Set<String>()
            for i in 0..<all.count {
                if self.scanShouldCancel { break }
                let asset = all.object(at: i)
                for res in self.syncableResources(for: asset) {
                    let name = res.originalFilename
                    let lSize = Int64(res.value(forKey: "fileSize") as? Int ?? 0)
                    if let df = driveMap[name] {
                        matched.insert(name)
                        results.append(DiffItem(fileName: name, localSize: lSize, driveSize: df.size, status: df.size == lSize ? .matched : .sizeMismatch, asset: asset, driveId: df.id))
                    } else {
                        results.append(DiffItem(fileName: name, localSize: lSize, driveSize: nil, status: .missingCloud, asset: asset, driveId: nil))
                    }
                }
                if i % 50 == 0 || i == all.count - 1 {
                    DispatchQueue.main.async { self.scanProgress = Double(i+1)/Double(all.count) }
                }
            }
            for (n, info) in driveMap where !matched.contains(n) {
                results.append(DiffItem(fileName: n, localSize: 0, driveSize: info.size, status: .extraCloud, asset: nil, driveId: info.id))
            }
            DispatchQueue.main.async { self.diffItems = results; self.isScanning = false }
        }
    }

    private func fetchGoogleDriveInfoFull(completion: @escaping ([(id: String, name: String, size: Int64)]) -> Void) {
        guard !googleAccessToken.isEmpty else { completion([]); return }
        var all: [(id: String, name: String, size: Int64)] = []
        var next: String? = nil
        let group = DispatchGroup()
        func fetch() {
            var urlStr = "https://www.googleapis.com/drive/v3/files?pageSize=1000&fields=files(id,name,size),nextPageToken"
            if let pt = next { urlStr += "&pageToken=\(pt)" }
            guard let u = URL(string: urlStr) else { return }
            var req = URLRequest(url: u)
            req.setValue("Bearer \(googleAccessToken)", forHTTPHeaderField: "Authorization")
            group.enter()
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                guard let data = data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let fs = j["files"] as? [[String: Any]] else { return }
                for f in fs {
                    if let n = f["name"] as? String, let id = f["id"] as? String {
                        all.append((id: id, name: n, size: Int64(f["size"] as? String ?? "0") ?? 0))
                    }
                }
                next = j["nextPageToken"] as? String
                if next != nil { fetch() }
            }.resume()
        }
        fetch()
        group.notify(queue: .global()) { completion(all) }
    }

    func logoutGoogle() {
        googleAccessToken = ""
        KeychainTokenStore.deleteRefreshToken()
        isGoogleConnected = false
        addLog("👋 Çıkış yapıldı.")
    }
}
