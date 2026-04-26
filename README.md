# SyncCloud — iCloud to Google Drive Sync (macOS)

SyncCloud is a privacy-focused macOS application designed to create a permanent backup of your iCloud Photo Library on Google Drive. It enforces a one-way synchronization policy, ensuring that your Google Drive functions as an immutable archive of your memories.

## 🚀 Features

- **One-Way Synchronization:** Data flows exclusively from iCloud to Google Drive.
- **Permanent Archive:** No files are ever deleted from Google Drive, even if they are removed from your local iCloud library.
- **Background Engine:** Runs quietly in the status bar, monitoring changes and uploading new photos automatically.
- **Diff View:** Transparently see the differences between your local library and the cloud backup.
- **Secure Token Management:** Uses macOS Keychain to securely store OAuth tokens.
- **Custom Filters:** Option to filter by media type or album.

## 🛠️ Prerequisites

- **macOS:** 14.0 (Sonoma) or newer.
- **Swift:** 5.9 or newer.
- **Google Cloud Console:** You will need a Google Cloud project with the Google Drive API enabled and OAuth 2.0 credentials.

## 🔐 Security & Privacy

SyncCloud is designed with security in mind:
- **No Hardcoded Secrets:** This repository does not contain any API keys or client secrets.
- **Local Storage:** All synchronization metadata and tokens are stored locally on your device.
- **OAuth 2.0:** Uses standard Google OAuth 2.0 for secure access to your Drive.

## ⚙️ Local Setup

To run this project locally, you need to provide your own Google OAuth credentials:

1. Clone the repository.
2. Create a file named `Secrets.plist` in the root directory.
3. Add your credentials to `Secrets.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>GoogleOAuthClientID</key>
       <string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
       <key>GoogleOAuthClientSecret</key>
       <string>YOUR_CLIENT_SECRET</string>
       <key>GoogleOAuthRedirectURI</key>
       <string>http://localhost:8080</string>
   </dict>
   </plist>
   ```
4. Build and run using Xcode or the provided `scripts/run.sh`.

## 📜 License

This project is licensed under the MIT License.
