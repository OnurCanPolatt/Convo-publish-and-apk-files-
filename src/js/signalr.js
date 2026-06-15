// SignalR Client-Side Connection - Stable Version
class SignalRManager {
    constructor() {
        this.connection = null;
        this.isConnected = false;
        this.currentUserId = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5; // Azaltıldı
        this.notificationComponent = null;
        this.isReconnecting = false; // Yeni: Çoklu reconnect önleme
        this.connectionLock = false; // Yeni: Connection lock
    }

    // SignalR bağlantısını başlat ve user'ı kaydet
    async start(userId) {
        // Eğer zaten bağlanma işlemi devam ediyorsa bekle
        if (this.connectionLock) {
            console.log("⏳ Connection already in progress, waiting...");
            return;
        }

        try {
            this.connectionLock = true;

            if (this.connection && this.connection.state !== "Disconnected") {
                console.log("🔄 Closing existing connection...");
                await this.stop();
            }

            this.currentUserId = userId;
            console.log(`🚀 SignalR starting for user: ${userId}`);

            // SignalR connection oluştur - Optimize edilmiş timeout ayarları
            const isDevelopment = window.location.hostname === 'localhost';

            this.connection = new signalR.HubConnectionBuilder()
                .withUrl("/chatHub", {
                    // ✅ Server timeout ayarlarıyla senkronize
                    // Development: 30 dakika, Production: 10 dakika
                    timeout: isDevelopment ? 1800000 : 600000,
                    // ✅ Transport stratejisi: WebSockets öncelikli
                    transport: signalR.HttpTransportType.WebSockets |
                               signalR.HttpTransportType.ServerSentEvents |
                               signalR.HttpTransportType.LongPolling,
                    // ✅ KeepAlive client-side interval (Server keepAlive'ın 2 katı olmalı)
                    // Server KeepAlive: Dev=2dk, Prod=15sn
                    keepAliveIntervalInMilliseconds: isDevelopment ? 240000 : 30000
                })
                .withAutomaticReconnect([1000, 3000, 5000, 15000, 30000])
                .configureLogging(signalR.LogLevel.Warning)
                .build();

            // Event listeners'ı kurma işlemini buraya taşı
            this.setupConnectionEvents();

            // Bağlantıyı başlat
            await this.connection.start();
            this.isConnected = true;
            this.reconnectAttempts = 0;
            this.isReconnecting = false;
            console.log("✅ SignalR connected");

            // ✅ dotNetObjectRef hazır olana kadar bekle (max 5 saniye)
            let waitCount = 0;
            while (!window.dotNetObjectRef && waitCount < 50) {
                await new Promise(resolve => setTimeout(resolve, 100)); // 100ms bekle
                waitCount++;
            }

            if (!window.dotNetObjectRef) {
                console.error("❌ dotNetObjectRef 5 saniye içinde set edilemedi!");
                throw new Error("dotNetObjectRef not available");
            }

            console.log("✅ dotNetObjectRef hazır, event listener'lar kuruluyor");
            
            this.setupAllEvents(); 
            console.log("✅ SignalR event listeners kuruldu");
            
            // ✅ SONRA user'ı kaydet (böylece BroadcastOnlineUsers geldiğinde handler hazır)
            await this.registerUser(userId);

        } catch (error) {
            console.error("💥 SignalR connection error:", error);
            this.isConnected = false;
            await this.handleConnectionError(userId);
        } finally {
            this.connectionLock = false;
        }
    }

    // Connection event'lerini ayrı metod olarak
    setupConnectionEvents() {
        this.connection.onreconnecting(() => {
            console.log("🔄 SignalR reconnecting...");
            this.isConnected = false;
            this.isReconnecting = true;
        });

        this.connection.onreconnected(async () => {
            console.log("✅ SignalR reconnected - Re-registering user and groups");
            this.isConnected = true;
            this.isReconnecting = false;
            this.reconnectAttempts = 0;

            try {
                // 1. Önce kullanıcıyı tekrar kaydet
                await this.registerUser(this.currentUserId);

                // 2. ✅ SONRA, C#'a haber ver ve gruplara yeniden katılmasını söyle
                if (window.dotNetObjectRef) {
                    await window.dotNetObjectRef.invokeMethodAsync('RejoinGroupsOnReconnect');
                    console.log("✅ Re-join groups command sent to Blazor.");
                } else {
                    console.warn("⚠️ dotNetObjectRef not found, cannot rejoin groups automatically.");
                }

            } catch (error) {
                console.error("❌ Re-registration or Re-join failed:", error);
            }
        });

        this.connection.onclose(async (error) => {
            console.log("❌ SignalR connection closed:", error?.message || "Normal close");
            this.isConnected = false;
            this.isReconnecting = false;

            // Manuel retry sadece beklenmeyen kopmalarda
            if (error && this.currentUserId && !this.connectionLock) {
                await this.handleConnectionError(this.currentUserId);
            }
        });
    }

    // Connection error handling - Daha kontrollü
    async handleConnectionError(userId) {
        if (this.reconnectAttempts < this.maxReconnectAttempts && !this.isReconnecting) {
            this.reconnectAttempts++;
            const delay = Math.min(2000 * this.reconnectAttempts, 30000); // Max 30 saniye
            console.log(`🔄 Reconnect attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts} in ${delay}ms`);

            setTimeout(async () => {
                if (!this.isConnected && !this.connectionLock) {
                    await this.start(userId);
                }
            }, delay);
        } else {
            console.error("❌ Max reconnect attempts reached or already reconnecting");
        }
    }

    // User'ı hub'a kaydet - Daha güvenli
    async registerUser(userId) {
        if (!this.isConnected) {
            console.error("❌ SignalR not connected, cannot register user");
            return false;
        }

        if (!userId) {
            console.error("❌ No userId provided for registration");
            return false;
        }

        try {
            console.log(`📝 Registering user: ${userId}`);
            await this.connection.invoke("RegisterUser", userId);
            console.log(`✅ User registered successfully: ${userId}`);
            return true;
        } catch (error) {
            console.error("❌ User registration failed:", error);
            return false;
        }
    }

    // Event listeners
    setupEventListeners() {
        this.setupAllEvents();
    }

    // Hub metodları - Connection state kontrolü eklendi
    async processFriendNotification(targetUserId, message, notificationType) {
        if (!this.ensureConnection()) return false;

        try {
            await this.connection.invoke("ProcessFriendNotification", targetUserId, message, notificationType);
            console.log("✅ Friend request sent");
            return true;
        } catch (error) {
            console.error("❌ Send friend request failed:", error);
            return false;
        }
    }

    async notifyConferenceStarted(roomId, currentUserId, userId) {
        if (!this.ensureConnection()) return false;

        try {
            await this.connection.invoke("NotifyConferenceStarted", roomId, currentUserId, userId);
            console.log("✅ Conference request sent");
            return true;
        } catch (error) {
            console.error("❌ Conference request failed:", error);
            return false;
        }
    }


    async sendMessage(receiverId, newMessage = null, fileUrl = null, messageType = null, filesize = null, isGroupMessage = false, messageId = null, sentAt = null) {
        if (!this.ensureConnection()) return false;

        try {
            const fileSizeParam = (filesize !== null && filesize !== undefined) ? Number(filesize) : 0;

            // ✅ sentAt her zaman client'tan gelmelidir (C# tarafından oluşturulmuş)
            if (!sentAt) {
                console.error("❌ sentAt parametresi boş! Bu bir hata.");
                sentAt = new Date().toISOString(); // Fallback
            }

            console.log(`📤 Hub'a gönderiliyor:`, {
                receiverId,
                messageId,
                sentAt,
                sentAtType: typeof sentAt
            });

            await this.connection.invoke("SendMessage",
                receiverId,
                newMessage,
                fileUrl,
                messageType,
                fileSizeParam,
                isGroupMessage,
                messageId,
                sentAt // ✅ ISO 8601 string olarak gitmeli
            );

            return true;
        } catch (error) {
            console.error("❌ Mesaj gönderimi başarısız:", error);
            return false;
        }
    }
    async joinMultipleGroups(groupIds) {
        if (!this.ensureConnection()) return false;

        try {
            await this.connection.invoke("JoinMultipleGroups", groupIds);
            console.log(`✅ Joined ${groupIds.length} groups`);
            return true;
        } catch (error) {
            console.error("❌ Join multiple groups failed:", error);
            return false;
        }
    }

    async leaveMultipleGroups(groupIds) {
        if (!this.ensureConnection()) return false;

        try {
            await this.connection.invoke("LeaveMultipleGroups", groupIds);
            console.log(`✅ Left ${groupIds.length} groups`);
            return true;
        } catch (error) {
            console.error("❌ Leave multiple groups failed:", error);
            return false;
        }
    }
    async notifyConferenceEnded(userId) {
        if (!this.ensureConnection()) return false;

        try {
            await this.connection.invoke("NotifyConferenceEnded", userId);
            return true;
        } catch (error) {
            console.error("❌ End Conference failed:", error);
            return false;
        }
    }
    async notifyGroupConferenceStarted(roomId, starterId, groupId) {
        if (!this.ensureConnection()) return false;

        try {
            // ✅ Sadece ID'leri gönder
            await this.connection.invoke(
                "NotifyGroupConferenceStarted",
                roomId,     // ← Room ID
                starterId ,// ← Starter ID
                groupId.toString()    // ← Grup ID

            );

            console.log("✅ Group Conference request sent");
            return true;
        } catch (error) {
            console.error("❌ Group Conference request failed:", error);
            return false;
        }
    }

    async notifyUserJoined(roomId, currentUserId, groupId) { // ✅ 'groupId' eklendi
        if (!this.ensureConnection()) return false;

        try {
            // ✅ 'groupId' Hub'a gönderiliyor
            await this.connection.invoke("NotifyGroupUserJoined", roomId, currentUserId, groupId);
            console.log(`✅ User joined notification sent for group: ${groupId}`);
            return true;
        } catch (error) {
            console.error("❌ User joined notification failed:", error);
            return false;
        }
    }

    async notifyGroupConferenceEnded(roomId, groupId) { // ✅ 'groupId' eklendi
        if (!this.ensureConnection()) return false;

        try {
            // ✅ 'groupId' Hub'a gönderiliyor
            await this.connection.invoke("NotifyGroupConferenceEnded", roomId, groupId);
            return true;
        } catch (error) {
            console.error("❌ End Conference failed:", error);
            return false;
        }
    }

    async notifyGroupUserLeft(roomId, currentUserId, groupId) { // ✅ 'groupId' eklendi
        if (!this.ensureConnection()) return false;

        try {
            // ✅ 'groupId' Hub'a gönderiliyor
            await this.connection.invoke("NotifyGroupUserLeft", roomId, currentUserId, groupId);
            return true;
        } catch (error) {
            console.error("❌ End Conference failed:", error);
            return false;
        }
    }
    async notifyGroupCreated(groupId) {
        if (!this.ensureConnection()) {
            console.error("❌ SignalR connection yok!");
            return;
        }

        try {
            console.log("🆕 NotifyGroupCreated çağrılıyor:", groupId);

            // ✅ TEK PARAMETRE GÖNDER
            await this.connection.invoke("NotifyGroupCreated", groupId);
            console.log("✅ NotifyGroupCreated başarılı");
        } catch (err) {
            console.error("❌ NotifyGroupCreated hatası:", err);
        }
    }
    async groupInfoUpdated(groupId) {
        if (!this.ensureConnection()) return false;

        try {
            await this.connection.invoke("GroupInfoUpdated", groupId);
            return true;
        } catch (error) {
            console.error("❌ End GroupInfoUpdate failed:", error);
            return false;
        }
    }
    async userInfoUpdated(userId) {
        if (!this.ensureConnection()) return false;

        try {
            await this.connection.invoke("UserInfoUpdated",userId);
            return true;
        } catch (error) {
            console.error("❌ End UserInfoUpdated failed:", error);
            return false;
        }
    }
    // ✅ YENİ: Aktif odayı sunucudan sorma metodu
    async getActiveRoomForGroup(groupId) {
        if (!this.ensureConnection()) {
            console.warn("❌ Aktif oda sorgulanamadı, SignalR bağlı değil.");
            return 0; // Bağlı değilse 0 döndür
        }
        try {
            // Hub'daki yeni GetActiveRoomForGroup metodunu çağır
            var roomId = await this.connection.invoke("GetActiveRoomForGroup", groupId);
            return roomId;
        } catch (error) {
            console.error("❌ getActiveRoomForGroup invoke hatası:", error);
            return 0; // Hata durumunda 0 döndür
        }
    }
    async joinGroup(groupId) {
        if (!this.ensureConnection()) return false;
        try {
            // Parametreyi array içine alarak joinMultipleGroups'a paslıyoruz
            await this.connection.invoke("JoinMultipleGroups", [groupId]);
            console.log(`✅ Joined group: ${groupId}`);
            return true;
        } catch (error) {
            console.error("❌ Join group failed:", error);
            return false;
        }
    }
    // Yeni: Connection durumu kontrolü
    ensureConnection() {
        if (!this.isConnected || this.connection?.state !== "Connected") {
            console.warn("❌ Not connected, operation cancelled");
            return false;
        }
        return true;
    }

    // Notification listener yönetimi
    addNotificationUpdateListener(component) {
        this.notificationComponent = component;
        console.log("✅ Notification listener eklendi");
    }

    removeNotificationUpdateListener() {
        this.notificationComponent = null;
        console.log("🧹 Notification listener kaldırıldı");
    }

    async stop() {
        if (this.connection) {
            try {
                this.clearAllEvents();
                await this.connection.stop();
                console.log("🛑 SignalR stopped");
            } catch (error) {
                console.log("🛑 SignalR stop error (normal):", error.message);
            }
            this.connection = null;
            this.isConnected = false;
            this.currentUserId = null;
            this.reconnectAttempts = 0;
            this.isReconnecting = false;
            this.connectionLock = false;
        }
    }

    // Connection durumunu kontrol et
    getConnectionState() {
        return {
            isConnected: this.isConnected,
            currentUserId: this.currentUserId,
            reconnectAttempts: this.reconnectAttempts,
            connectionState: this.connection?.state || "Disconnected",
            isReconnecting: this.isReconnecting
        };
    }
}

// Global instance
window.signalRManager = new SignalRManager();

// Blazor'dan çağrılacak
window.startSignalRWithUser = async function (userId) {
    console.log(`🎯 startSignalRWithUser called with:`, userId);

    if (!userId) {
        console.error("❌ No userId provided to startSignalRWithUser");
        return;
    }

    await window.signalRManager.start(userId.toString());
};

// Sayfa kapatılırken bağlantıyı kes
window.addEventListener('beforeunload', async function (event) {
    if (window.signalRManager && window.signalRManager.isConnected) {
        await window.signalRManager.stop();
    }
});

// Tab visibility - Daha kontrollü yaklaşım
document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible' && window.signalRManager && window.signalRManager.currentUserId) {
        const state = window.signalRManager.getConnectionState();

        // Sadece gerçekten bağlantı kopmuşsa ve reconnect devam etmiyorsa yeniden bağlan
        if (!state.isConnected && !state.isReconnecting && state.connectionState === "Disconnected") {
            console.log("🔄 Tab returned, checking connection...");
            setTimeout(() => {
                if (!window.signalRManager.connectionLock) {
                    window.signalRManager.start(state.currentUserId);
                }
            }, 1000); // 1 saniye bekle
        }
    }
});

// Blazor event listener yönetimi
window.dotNetObjectRef = null;

window.addSignalREventListeners = function (dotNetRef) {
    if (window.dotNetObjectRef) {
        console.log("🧹 Replacing existing dotNetObjectRef");
    }

    window.dotNetObjectRef = dotNetRef;
    console.log("✅ New dotNetObjectRef set");

    // SignalR bağlıysa event'leri kur
    if (window.signalRManager && window.signalRManager.connection && window.signalRManager.isConnected) {
        window.signalRManager.setupAllEvents();
    }
};

window.removeSignalREventListeners = function () {
    if (window.signalRManager && window.signalRManager.connection) {
        window.signalRManager.clearAllEvents();
    }

    window.dotNetObjectRef = null;
    console.log("🧹 Event listeners and dotNetRef removed");
};

// Debug fonksiyonu
window.getSignalRStatus = function () {
    return window.signalRManager.getConnectionState();
};

// Global dotNetRef setter
window.setGlobalDotNetRef = function (dotNetRef) {
    window.dotNetObjectRef = dotNetRef;
    console.log("✅ Global dotNetRef set:", dotNetRef);
};