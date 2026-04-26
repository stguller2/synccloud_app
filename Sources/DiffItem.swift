import Foundation
import Photos

/// Represents a single file comparison result between iCloud and Google Drive
struct DiffItem: Identifiable {
    let id = UUID()
    let fileName: String
    let localSize: Int64
    let driveSize: Int64?
    let status: DiffStatus
    let asset: PHAsset?
    let driveId: String?
    
    enum DiffStatus: String {
        case matched     = "Eşleşti"
        case sizeMismatch = "Uyumsuz Boyut"
        case missingCloud = "Bulutta Eksik"
        case extraCloud   = "Sadece Bulutta"
    }
    
    var statusIcon: String {
        switch status {
        case .matched:      return "checkmark.circle.fill"
        case .sizeMismatch: return "exclamationmark.triangle.fill"
        case .missingCloud: return "xmark.circle.fill"
        case .extraCloud:   return "cloud.fill"
        }
    }
    
    var statusColorName: String {
        switch status {
        case .matched:      return "green"
        case .sizeMismatch: return "orange"
        case .missingCloud: return "red"
        case .extraCloud:   return "blue"
        }
    }
    
    /// Human-readable file size
    static func formatSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "—" }
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var unitIndex = 0
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }
}
