import SwiftUI

struct FilterSettingsView: View {
    @ObservedObject var filter: SyncFilter
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.06), Color.purple.opacity(0.06)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerBar
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Master toggle
                        masterToggle
                        
                        if filter.isEnabled {
                            // Media Type
                            filterSection(title: "Medya Türü", icon: "photo.on.rectangle.angled") {
                                mediaTypeSection
                            }
                            
                            // Date Range
                            filterSection(title: "Tarih Aralığı", icon: "calendar") {
                                dateRangeSection
                            }
                            
                            // File Size
                            filterSection(title: "Dosya Boyutu", icon: "externaldrive") {
                                fileSizeSection
                            }
                            
                            // Format
                            filterSection(title: "Dosya Formatları", icon: "doc.badge.gearshape") {
                                formatSection
                            }
                        }
                        
                        // Summary
                        summarySection
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 450, height: 580)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
    }
    
    // MARK: - Header
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Akıllı Filtreler")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text("Hangi dosyaların senkronize edileceğini belirle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
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
    
    // MARK: - Master Toggle
    private var masterToggle: some View {
        HStack {
            Image(systemName: filter.isEnabled ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundColor(filter.isEnabled ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Filtreleri Etkinleştir")
                    .font(.system(size: 13, weight: .semibold))
                Text(filter.isEnabled ? "Kurallar aktif — sadece eşleşen dosyalar işlenir" : "Tüm dosyalar senkronize edilir")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $filter.isEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
                .labelsHidden()
        }
        .padding(12)
        .background(filter.isEnabled ? Color.blue.opacity(0.08) : Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(filter.isEnabled ? Color.blue.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Sections
    private func filterSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.blue.opacity(0.8))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            content()
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Media Type
    private var mediaTypeSection: some View {
        VStack(spacing: 6) {
            ForEach(SyncFilter.MediaType.allCases, id: \.self) { type in
                mediaTypeRow(type)
            }
        }
    }
    
    private func mediaTypeRow(_ type: SyncFilter.MediaType) -> some View {
        Button(action: { filter.mediaType = type }) {
            HStack {
                Image(systemName: filter.mediaType == type ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(filter.mediaType == type ? .blue : .secondary.opacity(0.4))
                    .font(.system(size: 14))
                
                Text(type.rawValue)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.8))
                
                Spacer()
                
                Image(systemName: mediaTypeIcon(type))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(filter.mediaType == type ? Color.blue.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func mediaTypeIcon(_ type: SyncFilter.MediaType) -> String {
        switch type {
        case .photosOnly: return "photo"
        case .videosOnly: return "video"
        case .all:        return "photo.stack"
        }
    }
    
    // MARK: - Date Range
    private var dateRangeSection: some View {
        Picker("", selection: $filter.dateRange) {
            ForEach(SyncFilter.DateRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
    
    // MARK: - File Size
    private var fileSizeSection: some View {
        Picker("", selection: $filter.maxFileSize) {
            ForEach(SyncFilter.MaxFileSize.allCases, id: \.self) { size in
                Text(size.rawValue).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
    
    // MARK: - Format
    private var formatSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                formatToggle("HEIC", isOn: $filter.formatFilter.heic, color: .blue)
                formatToggle("JPEG", isOn: $filter.formatFilter.jpeg, color: .green)
                formatToggle("PNG", isOn: $filter.formatFilter.png, color: .orange)
                formatToggle("GIF", isOn: $filter.formatFilter.gif, color: .purple)
            }
            HStack(spacing: 12) {
                formatToggle("RAW", isOn: $filter.formatFilter.raw, color: .red)
                formatToggle("MP4", isOn: $filter.formatFilter.mp4, color: .cyan)
                formatToggle("MOV", isOn: $filter.formatFilter.mov, color: .indigo)
                Spacer()
            }
        }
    }
    
    private func formatToggle(_ label: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundColor(isOn.wrappedValue ? color : .secondary.opacity(0.4))
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isOn.wrappedValue ? .primary.opacity(0.8) : .secondary.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isOn.wrappedValue ? color.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Summary
    private var summarySection: some View {
        HStack {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(filter.isEnabled
                 ? "\(filter.activeRuleCount) aktif kural · \(filter.summaryText)"
                 : "Tüm dosyalar filtresiz senkronize edilecek")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
            
            Spacer()
        }
        .padding(10)
        .background(Color.black.opacity(0.1))
        .cornerRadius(8)
    }
}
