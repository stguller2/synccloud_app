import SwiftUI

struct DiffView: View {
    @ObservedObject var syncManager: SyncManager
    @Environment(\.dismiss) var dismiss
    
    @State private var filterSelection: FilterType = .all
    
    enum FilterType: String, CaseIterable {
        case all          = "Tümü"
        case missingCloud = "Eksik"
        case sizeMismatch = "Uyumsuz"
        case matched      = "Eşleşen"
        case extraCloud   = "Sadece Bulut"
    }
    
    private var filteredItems: [DiffItem] {
        switch filterSelection {
        case .all:          return syncManager.diffItems
        case .missingCloud: return syncManager.diffItems.filter { $0.status == .missingCloud }
        case .sizeMismatch: return syncManager.diffItems.filter { $0.status == .sizeMismatch }
        case .matched:      return syncManager.diffItems.filter { $0.status == .matched }
        case .extraCloud:   return syncManager.diffItems.filter { $0.status == .extraCloud }
        }
    }
    
    private var matchedCount: Int { syncManager.diffItems.filter { $0.status == .matched }.count }
    private var mismatchCount: Int { syncManager.diffItems.filter { $0.status == .sizeMismatch }.count }
    private var missingCount: Int { syncManager.diffItems.filter { $0.status == .missingCloud }.count }
    private var extraCount: Int { syncManager.diffItems.filter { $0.status == .extraCloud }.count }
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.08), Color.purple.opacity(0.08)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerBar
                
                if syncManager.isScanning {
                    scanningView
                } else if syncManager.diffItems.isEmpty {
                    emptyView
                } else {
                    // Stats
                    statsBar
                    
                    // Filter Tabs
                    filterBar
                    
                    // Column headers
                    columnHeaders
                    
                    // File list
                    fileList
                }
            }
        }
        .frame(minWidth: 750, minHeight: 600)
        .frame(width: 850, height: 700)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
    }
    
    // MARK: - Header
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kıyaslama & Önizleme")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text("iCloud → Google Drive (Tek Yönlü Arşiv)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if syncManager.isScanning {
                Button(action: { syncManager.cancelScan() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Durdur")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { syncManager.scanDiff() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(syncManager.diffItems.isEmpty ? "Tara" : "Yenile")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
    
    // MARK: - Scanning
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: syncManager.scanProgress)
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [.blue, .purple, .blue]), center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(Int(syncManager.scanProgress * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Taranıyor")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Text("İki depolama arasındaki dosyalar karşılaştırılıyor...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    // MARK: - Empty
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("Henüz bir tarama yapılmadı")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("İki depolama arasındaki farkları görmek için\n\"Tara\" butonuna tıklayın.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Spacer()
        }
    }
    
    // MARK: - Stats Bar
    private var statsBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                statBadge(icon: "checkmark.circle.fill", color: .green, label: "Eşleşen", count: matchedCount)
                statBadge(icon: "exclamationmark.triangle.fill", color: .orange, label: "Uyumsuz", count: mismatchCount)
                statBadge(icon: "xmark.circle.fill", color: .red, label: "Eksik", count: missingCount)
                statBadge(icon: "cloud.fill", color: .blue, label: "Sadece Bulut", count: extraCount)
                
                Spacer()
                
                Text("Toplam: \(syncManager.diffItems.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            if (missingCount + mismatchCount) > 0 && !syncManager.isDiffUploading {
                HStack(spacing: 12) {
                    if (missingCount + mismatchCount) > 0 {
                        Button(action: { syncManager.uploadDiffIssues() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "icloud.and.arrow.up.fill")
                                Text("Eksikleri Yükle (\(missingCount + mismatchCount) dosya)")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(8)
                            .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            
            if syncManager.isDiffUploading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Yükleniyor: \(syncManager.diffUploadStatus)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { syncManager.cancelDiffUpload() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Durdur")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .background(Color.black.opacity(0.1))
    }
    
    private func statBadge(icon: String, color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Filter
    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(FilterType.allCases, id: \.self) { filter in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { filterSelection = filter } }) {
                    Text(filter.rawValue)
                        .font(.system(size: 11, weight: filterSelection == filter ? .bold : .regular))
                        .foregroundColor(filterSelection == filter ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(filterSelection == filter ? Color.blue.opacity(0.8) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // MARK: - Column Headers
    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Durum")
                .frame(width: 35, alignment: .center)
            
            Text("Dosya Adı")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            
            Text("iCloud")
                .frame(width: 100, alignment: .trailing)
            
            Text("→")
                .frame(width: 30, alignment: .center)
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Google Drive")
                .frame(width: 100, alignment: .trailing)
            
            Text("Fark")
                .frame(width: 90, alignment: .trailing)
                .padding(.trailing, 10)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.secondary.opacity(0.7))
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.15))
    }
    
    // MARK: - File List
    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems) { item in
                    diffRow(item)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(.horizontal, 10)
    }
    
    private func diffRow(_ item: DiffItem) -> some View {
        let statusColor: Color = {
            switch item.status {
            case .matched: return .green
            case .sizeMismatch: return .orange
            case .missingCloud: return .red
            case .extraCloud: return .blue
            }
        }()
        
        return HStack(spacing: 0) {
            Image(systemName: item.statusIcon)
                .font(.system(size: 12))
                .foregroundColor(statusColor)
                .frame(width: 35, alignment: .center)
            
            Text(item.fileName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            
            Text(DiffItem.formatSize(item.localSize))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.blue.opacity(0.9))
                .frame(width: 100, alignment: .trailing)
            
            Image(systemName: arrowIcon(for: item))
                .font(.system(size: 10))
                .foregroundColor(statusColor.opacity(0.6))
                .frame(width: 30, alignment: .center)
            
            Text(DiffItem.formatSize(item.driveSize ?? 0))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.red.opacity(0.9))
                .frame(width: 100, alignment: .trailing)
            
            Text(sizeDiffLabel(item))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor)
                .frame(width: 90, alignment: .trailing)
                .padding(.trailing, 10)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(statusColor.opacity(0.03))
        .cornerRadius(4)
    }
    
    private func arrowIcon(for item: DiffItem) -> String {
        switch item.status {
        case .matched:      return "equal.circle"
        case .sizeMismatch: return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .missingCloud: return "arrow.right"
        case .extraCloud:   return "cloud.fill"
        }
    }
    
    private func sizeDiffLabel(_ item: DiffItem) -> String {
        switch item.status {
        case .matched:
            return "✓ Tamam"
        case .sizeMismatch:
            let diff = item.localSize - (item.driveSize ?? 0)
            let prefix = diff > 0 ? "+" : ""
            return "\(prefix)\(DiffItem.formatSize(abs(diff)))"
        case .missingCloud:
            return "Yüklenmeli"
        case .extraCloud:
            return "Sadece Bulut"
        }
    }
}
