<div align="center">

# 🚀 Convo - Real-Time Communication Platform

[![Docker Hub](https://img.shields.io/badge/Docker-Hub-blue?logo=docker)](https://hub.docker.com/r/onurcanpolat/convoapp)
[![.NET 9](https://img.shields.io/badge/.NET-9.0-purple?logo=dotnet)](https://dotnet.microsoft.com/)
[![Blazor](https://img.shields.io/badge/Blazor-Hybrid-blue?logo=blazor)](https://dotnet.microsoft.com/apps/aspnet/web-apps/blazor)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Yüksek performanslı, gerçek zamanlı iletişim platformu**

[English](#english) | [Türkçe](#turkce)

</div>

---

<a name="turkce"></a>
## 🇹🇷 Türkçe

### 📱 Genel Bakış

Convo, .NET 9, Blazor Hybrid, SignalR ve Janus WebRTC Gateway kullanılarak geliştirilmiş modern bir gerçek zamanlı iletişim platformudur. Hem web hem de mobil platformlarda çalışan tam özellikli bir mesajlaşma ve video konferans uygulamasıdır.

### ✨ Özellikler

- 💬 **Gerçek Zamanlı Mesajlaşma**: SignalR ile anlık mesajlaşma
- 📁 **Dosya Paylaşımı**: MinIO S3 uyumlu depolama ile dosya transferi
- 🎥 **Video Konferans**: Janus WebRTC Gateway ile yüksek kaliteli video/ses görüşmeleri
- 👥 **Grup Sohbetleri**: Çoklu kullanıcı grup sohbetleri oluşturma ve yönetme
- 👤 **Profil Yönetimi**: Kişiselleştirilebilir kullanıcı profilleri
- 🗑️ **Sohbet Yönetimi**: Sohbetleri silme ve düzenleme özellikleri
- 🌐 **Cross-Platform**: Web ve Android mobil uygulama desteği

### 🛠️ Teknoloji Stack

| Kategori | Teknoloji |
|----------|-----------|
| **Backend** | .NET 9, ASP.NET Core |
| **Frontend** | Blazor Hybrid |
| **Gerçek Zamanlı İletişim** | SignalR |
| **Video/Ses** | Janus WebRTC Gateway |
| **Depolama** | MinIO (S3-uyumlu) |
| **Veritabanı** | SQLite |
| **Konteynerizasyon** | Docker |
| **Reverse Proxy** | Nginx |

### 📦 Installation

To install Convo, follow the detailed installation guide on Docker Hub. The guide includes Docker Compose configuration, Janus media server setup, Nginx configuration, and SSL certificate installation.

[![Docker Hub Installation Guide](https://img.shields.io/badge/Installation_Guide-Docker_Hub-blue?logo=docker&style=for-the-badge)](https://hub.docker.com/r/onurcanpolat/convoapp)

The Docker Hub guide provides complete instructions for:
- Creating Docker Compose configuration
- Janus WebRTC Gateway setup
- MinIO storage configuration
- Nginx reverse proxy setup
- SSL/HTTPS certificate installation

### 📱 Mobil Uygulama

Android APK dosyasını buradan indirebilirsiniz:

[![Download APK](https://img.shields.io/badge/Download-APK_v1.0-green?style=for-the-badge&logo=android)](https://github.com/OnurCanPolatt/Convo-publish-and-apk-files-/releases/tag/v1.0)

**Sistem Gereksinimleri:**
- Android 7.0 (API 24) veya üzeri
- 101.75 MB boş depolama alanı
- İnternet bağlantısı

### 🖼️ Ekran Görüntüleri
 <summary>📱 Mobil Uygulama Görüntüleri</summary>

<p align="center"> <img src="https://github.com/user-attachments/assets/701b6bed-1abc-46c7-8bdb-ceb6bacbfd0a" width="220">

</p> </details>

<summary>🌐 Web Arayüzü Görüntüleri</summary>

<p align="center"> <img src="https://github.com/user-attachments/assets/a6ee93c1-7ddf-44e9-89f8-ad47149734f9" width="700">

 </p>

</details>

### 🔧 Geliştirme
```bash
# Repository'yi klonlayın
git clone https://github.com/OnurCanPolatt/Convo-publish-and-apk-files-.git

# Docker ile çalıştırın
cd Convo-publish-and-apk-files-
docker compose up -d
```

### 👨‍💻 Geliştirici

**Onur Can Polat**

- GitHub: [@OnurCanPolatt](https://github.com/OnurCanPolatt)
- Docker Hub: [onurcanpolat](https://hub.docker.com/u/onurcanpolat)


<a name="english"></a>
## 🇬🇧 English

### 📱 Overview

Convo is a modern real-time communication platform built with .NET 9, Blazor Hybrid, SignalR, and Janus WebRTC Gateway. It's a full-featured messaging and video conferencing application that works on both web and mobile platforms.

### ✨ Features

- 💬 **Real-Time Messaging**: Instant messaging with SignalR
- 📁 **File Sharing**: File transfer with MinIO S3-compatible storage
- 🎥 **Video Conferencing**: High-quality video/audio calls with Janus WebRTC Gateway
- 👥 **Group Chats**: Create and manage multi-user group conversations
- 👤 **Profile Management**: Customizable user profiles
- 🗑️ **Chat Management**: Delete and edit conversations
- 🌐 **Cross-Platform**: Web and Android mobile app support

### 🛠️ Tech Stack

| Category | Technology |
|----------|-----------|
| **Backend** | .NET 9, ASP.NET Core |
| **Frontend** | Blazor Hybrid |
| **Real-Time Communication** | SignalR |
| **Video/Audio** | Janus WebRTC Gateway |
| **Storage** | MinIO (S3-compatible) |
| **Database** | SQLite |
| **Containerization** | Docker |
| **Reverse Proxy** | Nginx |

### 📦 Installation

#### Quick Start with Docker

Visit our Docker Hub page for detailed installation instructions:

For detailed setup steps and configuration, see the [Docker Hub README](https://hub.docker.com/r/onurcanpolat/convoapp).

### 📱 Mobile App

Download the Android APK here:

[![Download APK](https://img.shields.io/badge/Download-APK_v1.0-green?style=for-the-badge&logo=android)](https://github.com/OnurCanPolatt/Convo-publish-and-apk-files-/releases/tag/v1.0)

**System Requirements:**
- Android 7.0 (API 24) or higher
- 101.75 MB free storage
- Internet connection

### 🖼️ Screenshots

<summary>📱 Mobil App Demo</summary>

<p align="center"> <img src="https://github.com/user-attachments/assets/701b6bed-1abc-46c7-8bdb-ceb6bacbfd0a" width="220" >

 </p> </details>

<summary>🌐 Web App Demo</summary>

<p align="center"> <img src="https://github.com/user-attachments/assets/a6ee93c1-7ddf-44e9-89f8-ad47149734f9" width="700" >

</p>

</details>

### 🔧 Development
```bash
# Clone the repository
git clone https://github.com/OnurCanPolatt/Convo-publish-and-apk-files-.git

# Run with Docker
cd Convo-publish-and-apk-files-
docker compose up -d
```
### 👨‍💻 Developer

**Onur Can Polat**

- GitHub: [@OnurCanPolatt](https://github.com/OnurCanPolatt)
- Docker Hub: [onurcanpolat](https://hub.docker.com/u/onurcanpolat)
