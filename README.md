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

### 📦 Kurulum

#### Docker ile Hızlı Başlangıç

Detaylı kurulum talimatları için Docker Hub sayfamızı ziyaret edin:

[![Docker Hub](https://img.shields.io/badge/Kurulum_Rehberi-Docker_Hub-blue?logo=docker&style=for-the-badge)](https://hub.docker.com/r/onurcanpolat/convoapp)

**Hızlı Kurulum:**
```bash
# Proje dizinini oluştur
mkdir ~/Convo && cd ~/Convo

# Docker Compose dosyasını indir
curl -O https://raw.githubusercontent.com/OnurCanPolatt/Convo-publish-and-apk-files-/main/docker-compose.yml

# Servisleri başlat
docker compose up -d
```

Detaylı kurulum adımları ve yapılandırma bilgileri için [Docker Hub README](https://hub.docker.com/r/onurcanpolat/convoapp) sayfasına bakın.

### 📱 Mobil Uygulama

Android APK dosyasını buradan indirebilirsiniz:

[![Download APK](https://img.shields.io/badge/Download-APK_v1.0-green?style=for-the-badge&logo=android)](https://github.com/OnurCanPolatt/Convo-publish-and-apk-files-/releases/tag/v1.0)

**Sistem Gereksinimleri:**
- Android 7.0 (API 24) veya üzeri
- 100 MB boş depolama alanı
- İnternet bağlantısı

### 🖼️ Ekran Görüntüleri
<details> <summary>📱 Mobil Uygulama Görüntüleri</summary>

<p align="center"> <img src="https://github.com/user-attachments/assets/701b6bed-1abc-46c7-8bdb-ceb6bacbfd0a" width="220">

<i>📱 Convo Mobile App Interface</i> </p> </details>

<details> <summary>🌐 Web Arayüzü Görüntüleri</summary>

<p align="center"> <img src="https://github.com/user-attachments/assets/a6ee93c1-7ddf-44e9-89f8-ad47149734f9" width="700">

<i>🌐 Convo Web Interface</i> </p>

</details>

### 🔧 Geliştirme
```bash
# Repository'yi klonlayın
git clone https://github.com/OnurCanPolatt/Convo-publish-and-apk-files-.git

# Docker ile çalıştırın
cd Convo-publish-and-apk-files-
docker compose up -d
```

### 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır. Detaylar için [LICENSE](LICENSE) dosyasına bakın.

### 👨‍💻 Geliştirici

**Onur Can Polat**

- GitHub: [@OnurCanPolatt](https://github.com/OnurCanPolatt)
- Docker Hub: [onurcanpolat](https://hub.docker.com/u/onurcanpolat)

### 🤝 Katkıda Bulunma

Katkılarınızı bekliyoruz! Lütfen pull request göndermekten çekinmeyin.

1. Fork edin
2. Feature branch oluşturun (`git checkout -b feature/YeniOzellik`)
3. Değişikliklerinizi commit edin (`git commit -m 'Yeni özellik eklendi'`)
4. Branch'inizi push edin (`git push origin feature/YeniOzellik`)
5. Pull Request oluşturun

---

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

[![Docker Hub](https://img.shields.io/badge/Installation_Guide-Docker_Hub-blue?logo=docker&style=for-the-badge)](https://hub.docker.com/r/onurcanpolat/convoapp)

**Quick Setup:**
```bash
# Create project directory
mkdir ~/Convo && cd ~/Convo

# Download Docker Compose file
curl -O https://raw.githubusercontent.com/OnurCanPolatt/Convo-publish-and-apk-files-/main/docker-compose.yml

# Start services
docker compose up -d
```

For detailed setup steps and configuration, see the [Docker Hub README](https://hub.docker.com/r/onurcanpolat/convoapp).

### 📱 Mobile App

Download the Android APK here:

[![Download APK](https://img.shields.io/badge/Download-APK_v1.0-green?style=for-the-badge&logo=android)](https://github.com/OnurCanPolatt/Convo-publish-and-apk-files-/releases/tag/v1.0)

**System Requirements:**
- Android 7.0 (API 24) or higher
- 100 MB free storage
- Internet connection

### 🖼️ Screenshots

<details> <summary>📱 Mobil App Demo</summary>

<p align="center"> <img src="https://github.com/user-attachments/assets/701b6bed-1abc-46c7-8bdb-ceb6bacbfd0a" width="220" >

 </p> </details>

<details> <summary>🌐 Web App Demo</summary>

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

### 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### 👨‍💻 Developer

**Onur Can Polat**

- GitHub: [@OnurCanPolatt](https://github.com/OnurCanPolatt)
- Docker Hub: [onurcanpolat](https://hub.docker.com/u/onurcanpolat)

### 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

<div align="center">

**Built with ❤️ using .NET 9, Blazor, SignalR & Janus WebRTC**

</div>
