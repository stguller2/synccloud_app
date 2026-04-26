import Foundation
import Photos

/// Smart filter configuration for controlling which files get synced
final class SyncFilter: ObservableObject {
    
    // MARK: - Media Type
    enum MediaType: String, CaseIterable {
        case photosOnly   = "Sadece Fotoğraflar"
        case videosOnly   = "Sadece Videolar"
        case all          = "Tümü (Fotoğraf + Video)"
    }
    
    // MARK: - Date Range
    enum DateRange: String, CaseIterable {
        case allTime      = "Tüm Zamanlar"
        case lastWeek     = "Son 1 Hafta"
        case lastMonth    = "Son 1 Ay"
        case last3Months  = "Son 3 Ay"
        case last6Months  = "Son 6 Ay"
        case lastYear     = "Son 1 Yıl"
        
        var date: Date? {
            let calendar = Calendar.current
            switch self {
            case .allTime:     return nil
            case .lastWeek:    return calendar.date(byAdding: .day, value: -7, to: Date())
            case .lastMonth:   return calendar.date(byAdding: .month, value: -1, to: Date())
            case .last3Months: return calendar.date(byAdding: .month, value: -3, to: Date())
            case .last6Months: return calendar.date(byAdding: .month, value: -6, to: Date())
            case .lastYear:    return calendar.date(byAdding: .year, value: -1, to: Date())
            }
        }
    }
    
    // MARK: - Max File Size
    enum MaxFileSize: String, CaseIterable {
        case noLimit  = "Sınırsız"
        case max5MB   = "Maks 5 MB"
        case max10MB  = "Maks 10 MB"
        case max25MB  = "Maks 25 MB"
        case max50MB  = "Maks 50 MB"
        case max100MB = "Maks 100 MB"
        
        var bytes: Int64? {
            switch self {
            case .noLimit:  return nil
            case .max5MB:   return 5 * 1024 * 1024
            case .max10MB:  return 10 * 1024 * 1024
            case .max25MB:  return 25 * 1024 * 1024
            case .max50MB:  return 50 * 1024 * 1024
            case .max100MB: return 100 * 1024 * 1024
            }
        }
    }
    
    // MARK: - Format Filter
    struct FormatFilter {
        var heic: Bool = true
        var jpeg: Bool = true
        var png: Bool = true
        var gif: Bool = true
        var raw: Bool = true
        var mp4: Bool = true
        var mov: Bool = true
        
        var allowedExtensions: Set<String> {
            var exts = Set<String>()
            if heic { exts.formUnion(["heic", "heif"]) }
            if jpeg { exts.formUnion(["jpg", "jpeg"]) }
            if png  { exts.insert("png") }
            if gif  { exts.insert("gif") }
            if raw  { exts.formUnion(["dng", "cr2", "nef", "arw"]) }
            if mp4  { exts.insert("mp4") }
            if mov  { exts.insert("mov") }
            return exts
        }
    }
    
    // MARK: - Published Properties
    @Published var mediaType: MediaType = .photosOnly {
        didSet { save() }
    }
    @Published var dateRange: DateRange = .allTime {
        didSet { save() }
    }
    @Published var maxFileSize: MaxFileSize = .noLimit {
        didSet { save() }
    }
    @Published var formatFilter: FormatFilter = FormatFilter() {
        didSet { save() }
    }
    @Published var isEnabled: Bool = false {
        didSet { save() }
    }
    
    // MARK: - Init
    init() {
        load()
    }
    
    // MARK: - Persistence
    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: "filter_enabled")
        defaults.set(mediaType.rawValue, forKey: "filter_mediaType")
        defaults.set(dateRange.rawValue, forKey: "filter_dateRange")
        defaults.set(maxFileSize.rawValue, forKey: "filter_maxFileSize")
        defaults.set(formatFilter.heic, forKey: "filter_fmt_heic")
        defaults.set(formatFilter.jpeg, forKey: "filter_fmt_jpeg")
        defaults.set(formatFilter.png, forKey: "filter_fmt_png")
        defaults.set(formatFilter.gif, forKey: "filter_fmt_gif")
        defaults.set(formatFilter.raw, forKey: "filter_fmt_raw")
        defaults.set(formatFilter.mp4, forKey: "filter_fmt_mp4")
        defaults.set(formatFilter.mov, forKey: "filter_fmt_mov")
    }
    
    private func load() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: "filter_enabled")
        
        if let mt = defaults.string(forKey: "filter_mediaType"),
           let val = MediaType(rawValue: mt) { mediaType = val }
        if let dr = defaults.string(forKey: "filter_dateRange"),
           let val = DateRange(rawValue: dr) { dateRange = val }
        if let ms = defaults.string(forKey: "filter_maxFileSize"),
           let val = MaxFileSize(rawValue: ms) { maxFileSize = val }
        
        if defaults.object(forKey: "filter_fmt_heic") != nil {
            formatFilter.heic = defaults.bool(forKey: "filter_fmt_heic")
            formatFilter.jpeg = defaults.bool(forKey: "filter_fmt_jpeg")
            formatFilter.png  = defaults.bool(forKey: "filter_fmt_png")
            formatFilter.gif  = defaults.bool(forKey: "filter_fmt_gif")
            formatFilter.raw  = defaults.bool(forKey: "filter_fmt_raw")
            formatFilter.mp4  = defaults.bool(forKey: "filter_fmt_mp4")
            formatFilter.mov  = defaults.bool(forKey: "filter_fmt_mov")
        }
    }
    
    // MARK: - Build PHFetchOptions
    func buildFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        var predicates: [NSPredicate] = []
        
        // Date filter
        if let startDate = dateRange.date {
            predicates.append(NSPredicate(format: "creationDate >= %@", startDate as NSDate))
        }
        
        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }
    
    /// Returns the PHAssetMediaType(s) to fetch
    func assetMediaTypes() -> [PHAssetMediaType] {
        switch mediaType {
        case .photosOnly: return [.image]
        case .videosOnly: return [.video]
        case .all:        return [.image, .video]
        }
    }
    
    /// Check if a specific file passes the filter
    func shouldInclude(fileName: String, fileSize: Int64) -> Bool {
        guard isEnabled else { return true }
        
        // Format filter
        let ext = (fileName as NSString).pathExtension.lowercased()
        if !ext.isEmpty && !formatFilter.allowedExtensions.contains(ext) {
            return false
        }
        
        // Size filter
        if let maxBytes = maxFileSize.bytes, fileSize > maxBytes {
            return false
        }
        
        return true
    }
    
    /// Summary string for display
    var summaryText: String {
        guard isEnabled else { return "Filtre kapalı" }
        
        var parts: [String] = []
        parts.append(mediaType.rawValue)
        if dateRange != .allTime { parts.append(dateRange.rawValue) }
        if maxFileSize != .noLimit { parts.append(maxFileSize.rawValue) }
        return parts.joined(separator: " · ")
    }
    
    /// Count of active filter rules
    var activeRuleCount: Int {
        guard isEnabled else { return 0 }
        var count = 0
        if mediaType != .all { count += 1 }
        if dateRange != .allTime { count += 1 }
        if maxFileSize != .noLimit { count += 1 }
        let fmt = formatFilter
        if !fmt.heic || !fmt.jpeg || !fmt.png || !fmt.gif || !fmt.raw || !fmt.mp4 || !fmt.mov {
            count += 1
        }
        return count
    }
}
