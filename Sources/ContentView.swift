import SwiftUI

struct ContentView: View {
    @StateObject private var syncManager = SyncManager()
    @StateObject private var authManager = GoogleAuthManager()
    @State private var isSyncing = false
    @State private var progress: Double = 0.0
    @State private var showLoginAlert = false
    @State private var loginAlertMessage = ""
    @State private var showDiffView = false
    @State private var showFilterView = false
    @EnvironmentObject var backgroundEngine: BackgroundSyncEngine

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                headerSection

                HStack(spacing: 15) {
                    StatusCard(title: "iCloud Photos",
                               status: syncManager.isPermissionGranted ? "\(syncManager.totalPhotoCount) Fotoğraf" : "İzin Ver",
                               systemImage: "icloud.fill",
                               accentColor: Color.blue,
                               isConnected: syncManager.isPermissionGranted)
                    .onTapGesture {
                        if !syncManager.isPermissionGranted { syncManager.requestPermission() }
                    }

                    StatusCard(title: "Google Drive",
                               status: syncManager.isGoogleConnected ? "Bağlı" : "Giriş Yap",
                               systemImage: "square.and.arrow.up.fill",
                               accentColor: Color.red,
                               isConnected: syncManager.isGoogleConnected)
                    .onTapGesture {
                        if !syncManager.isGoogleConnected { beginGoogleLogin() }
                    }
                }
                .padding(.horizontal)

                mainActionPanel

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ETKİNLİK")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 5)
                            
                        Spacer()
                        
                        Button(action: {
                            let logText = syncManager.syncLogs.reversed().joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(logText, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                            Text("Kopyala")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.8))
                        .padding(.trailing, 5)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if syncManager.syncLogs.isEmpty {
                                Text("Henüz bir işlem yapılmadı.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            ForEach(syncManager.syncLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 2)
                                    .transition(.opacity)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(width: 500, height: 200)
                    .padding(10)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                // Background Sync Controls
                if syncManager.isGoogleConnected {
                    backgroundSyncPanel
                }

                HStack {
                    if syncManager.isGoogleConnected {
                        Button("Çıkış Yap") {
                            syncManager.logoutGoogle()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(Color.red.opacity(0.7))
                    }
                    Spacer()
                    Text("V1.4.0 Stable")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal)
            }
            .padding(25)
        }
        .frame(minWidth: 500, minHeight: 750)
        .frame(width: 600, height: 900)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        .alert("Google girişi", isPresented: $showLoginAlert) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(loginAlertMessage)
        }
        .sheet(isPresented: $showDiffView) {
            DiffView(syncManager: syncManager)
        }
        .sheet(isPresented: $showFilterView) {
            FilterSettingsView(filter: syncManager.syncFilter)
        }
        .onAppear {
            backgroundEngine.syncManager = syncManager
        }
    }

    private func beginGoogleLogin() {
        authManager.signIn { outcome in
            switch outcome {
            case .success(let token):
                syncManager.googleAccessToken = token
                syncManager.isGoogleConnected = true
                syncManager.addLog("✅ Google Drive bağlandı.")
            case .failure(let message):
                loginAlertMessage = message
                showLoginAlert = true
                syncManager.addLog("❌ Google: \(message)")
            }
        }
    }

    private var mainActionPanel: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 12)
                    .frame(width: 150, height: 150)

                Circle()
                    .trim(from: 0, to: syncManager.isPermissionGranted ? progress : 0)
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [Color.blue, Color.purple, Color.blue]), center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))

                VStack {
                    if syncManager.isPermissionGranted {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 35, weight: .bold, design: .rounded))
                        Text(isSyncing ? "Transferde" : "Hazır")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "lock.fill").font(.title)
                    }
                }
            }
            .padding(.vertical, 10)

            Button(action: handleMainAction) {
                Text(actionButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(actionButtonColor)
                    .cornerRadius(12)
                    .shadow(color: actionButtonColor.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 40)

            if syncManager.isGoogleConnected && !isSyncing {
                HStack(spacing: 20) {
                    Button(action: { 
                        if syncManager.isVerifying {
                            syncManager.cancelVerify()
                        } else {
                            syncManager.verifySync()
                        }
                    }) {
                        HStack {
                            Image(systemName: syncManager.isVerifying ? "xmark.circle" : "checkmark.circle.badge.questionmark")
                            Text(syncManager.isVerifying ? "Doğrulamayı Durdur" : "Doğrula")
                        }
                        .font(.subheadline)
                        .foregroundColor(syncManager.isVerifying ? .red : .blue.opacity(0.8))
                        .padding(.top, 5)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { showDiffView = true }) {
                        HStack {
                            Image(systemName: "arrow.left.arrow.right.square")
                            Text("Kıyasla")
                        }
                        .font(.subheadline)
                        .foregroundColor(.purple.opacity(0.9))
                        .padding(.top, 5)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { showFilterView = true }) {
                        HStack(spacing: 3) {
                            Image(systemName: syncManager.syncFilter.isEnabled 
                                ? "line.3.horizontal.decrease.circle.fill" 
                                : "line.3.horizontal.decrease.circle")
                            Text("Filtre")
                            if syncManager.syncFilter.isEnabled && syncManager.syncFilter.activeRuleCount > 0 {
                                Text("\(syncManager.syncFilter.activeRuleCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(syncManager.syncFilter.isEnabled ? .green : .secondary.opacity(0.7))
                        .padding(.top, 5)
                    }
                    .buttonStyle(.plain)
                    
                    if syncManager.needsRepair && !syncManager.isVerifying {
                        Button(action: { syncManager.repairIssues() }) {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                Text("Onar")
                            }
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .padding(.top, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }

    private func handleMainAction() {
        if !syncManager.isPermissionGranted {
            syncManager.requestPermission()
        } else if !syncManager.isGoogleConnected {
            beginGoogleLogin()
        } else {
            toggleSync()
        }
    }

    private var actionButtonText: String {
        if !syncManager.isPermissionGranted { return "Fotoğraflara Erişime İzin Ver" }
        if !syncManager.isGoogleConnected { return "Google Drive'a Bağlan" }
        return isSyncing ? "Senkronizasyonu Durdur" : "Senkronizasyonu Başlat"
    }

    private var actionButtonColor: Color {
        if !syncManager.isPermissionGranted { return Color.orange }
        if !syncManager.isGoogleConnected { return Color.red }
        return isSyncing ? Color.red : Color.blue
    }

    private func toggleSync() {
        if isSyncing {
            syncManager.cancelSync()
            withAnimation { isSyncing = false }
            return
        }
        withAnimation { isSyncing = true }
        progress = 0
        syncManager.startSync(
            progressCallback: { newProgress in
                withAnimation { self.progress = newProgress }
            },
            finished: {
                withAnimation { self.isSyncing = false }
            }
        )
    }

    // MARK: - Background Sync Panel
    private var backgroundSyncPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: backgroundEngine.isEnabled 
                    ? "arrow.triangle.2.circlepath.icloud.fill" 
                    : "icloud.slash")
                    .foregroundColor(backgroundEngine.isEnabled ? .green : .secondary)
                    .font(.system(size: 14))
                
                Text("Arka Plan Senkronizasyonu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary.opacity(0.8))
                
                Spacer()
                
                Toggle("", isOn: $backgroundEngine.isEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .labelsHidden()
            }
            
            if backgroundEngine.isEnabled {
                HStack(spacing: 8) {
                    // Interval picker
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $backgroundEngine.syncInterval) {
                            ForEach(BackgroundSyncEngine.SyncInterval.allCases, id: \.self) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .scaleEffect(0.85)
                    }
                    
                    Spacer()
                    
                    // Status
                    HStack(spacing: 4) {
                        if backgroundEngine.isBackgroundSyncing {
                            ProgressView()
                                .scaleEffect(0.4)
                                .frame(width: 12, height: 12)
                        } else {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                        
                        Text(backgroundEngine.statusMessage)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let lastDate = backgroundEngine.lastSyncDate {
                    HStack {
                        Text("Son kontrol: \(lastDate, style: .relative) önce")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(backgroundEngine.isEnabled ? Color.green.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SyncCloud")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Text("iCloud → Google Drive Yedekleme")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isSyncing {
                ProgressView().scaleEffect(0.6)
            }
        }
    }
}

struct StatusCard: View {
    let title: String
    let status: String
    let systemImage: String
    let accentColor: Color
    let isConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(accentColor)
                    .font(.title2)
                Spacer()
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(status)
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
