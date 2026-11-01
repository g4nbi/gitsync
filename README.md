# Gitsync

Simple native iOS app to push files or folders from your device to GitHub.

- **Login via Device Code Flow** (recommended) — masukkan Client ID, dapat kode pendek, approve di browser GitHub. Password tidak pernah lewat app.
- Atau Personal Access Token
- Buat repo baru
- Pilih file / folder dari Files app → push sebagai **satu commit**
- Clean native SwiftUI, privacy-first (Keychain)
- iOS 17+

## Auth Flow (Device Code)

1. App minta **Client ID** (dari OAuth App kamu).
2. App POST ke `https://github.com/login/device/code` → dapat `user_code` + `device_code`.  
   Scope: `repo delete_repo workflow`
3. Kamu buka `github.com/login/device`, tempel `user_code`, Authorize.
4. App polling `/login/oauth/access_token` tiap ~5 detik sampai dapat token.
5. Token divalidasi dengan `/user`, lalu disimpan di **Keychain** (fallback UserDefaults).

## Setup OAuth App (wajib untuk Device Flow)

1. https://github.com/settings/developers → **OAuth Apps** → New OAuth App
2. Application name: `Gitsync`
3. Homepage URL: bebas (mis. `https://github.com`)
4. Authorization callback URL: `http://127.0.0.1` (Device Flow tidak pakai redirect, tapi field wajib diisi)
5. Register → copy **Client ID**
6. Di app, paste Client ID di layar login.

Tidak perlu Client Secret.

## Setup Xcode

1. New iOS App project → Product Name `Gitsync`, SwiftUI, iOS 17+
2. Hapus ContentView & App bawaan
3. Drag semua file di folder `Gitsync/` ke project (Create groups)
4. Build & run

## Personal Access Token (alternatif)

https://github.com/settings/tokens → classic → scope `repo` (dan `delete_repo` / `workflow` kalau mau).

## Build unsigned IPA

Ada workflow `.github/workflows/build-ipa.yml`.  
Setelah project punya `.xcodeproj`, push lalu jalankan workflow → artifact IPA unsigned.

## Struktur

```
Gitsync/
├── GitsyncApp.swift
├── ContentView.swift
├── Models/Models.swift
├── Services/
│   ├── AuthService.swift      ← Device Flow + PAT
│   ├── KeychainService.swift
│   └── GitHubService.swift
└── Views/
    ├── LoginView.swift
    ├── HomeView.swift
    ├── CreateRepoView.swift
    └── PushView.swift
```
