// ✅ SignalR Event Handlers - Optimized with Event Cleanup
SignalRManager.prototype.setupAllEvents = function () {
    // ✅ ÖNCE TÜM ESKİ EVENT'LERİ TEMİZLE
    this.clearAllEvents();

    console.log("🧹 Event listeners temizlendi, yenileri ekleniyor...");

    // ✅ Mesaj event'leri
    this.connection.on("ReceiveMessage", (senderId, newMessage, fileUrl, messageType,filesize, groupId,messageId, receiverId,sentAt) => {
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleReceiveMessage',
                senderId, newMessage, fileUrl, messageType, filesize,groupId,messageId, receiverId,sentAt
            ).catch(error => {
                console.error("❌ HandleReceiveMessage error:", error);
            });
        } else {
            console.warn("❌ dotNetObjectRef is null in ReceiveMessage");
        }
    });

    // ✅ Friend notification event'leri
    this.connection.on("FriendInfo", (fromUser, message) => {
        console.log("👥 FriendInfo received from:", fromUser);
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleUpdateUser', fromUser, message)
                .catch(error => console.error("❌ HandleUpdateUser error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in FriendInfo");
        }
    });

    // ✅ MyInfo event
    this.connection.on("MyInfo", () => {
        console.log("🔄 Self UI update requested");
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleUpdateMyself')
                .catch(error => console.error("❌ HandleUpdateMyself error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in MyInfo");
        }
    });

    // ✅ Online users event
    this.connection.on("OnlineUsersList", (users) => {
        console.log("👥 Online users received:", users?.length || 0, "users");
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync("HandleGetOnlineUsers", users || [])
                .catch(error => console.error("❌ HandleGetOnlineUsers error:", error));
        } else {        
            console.warn("❌ dotNetObjectRef is null in OnlineUsersList");
        }
    });

    // ✅ Notification event'leri
    this.connection.on("UnreadNotificationsLoaded", (notifications, notificationsCount) => {
        console.log(`🔔 Unread notifications received: ${notificationsCount}`);
        if (window.dotNetObjectRef) {
            if (notificationsCount > 0) {
                window.dotNetObjectRef.invokeMethodAsync("HandleUnreadNotifications", notifications, notificationsCount)
                    .catch(error => console.error("❌ HandleUnreadNotifications error:", error));
            }
        } else {
            console.warn("❌ dotNetObjectRef is null in UnreadNotificationsLoaded");
        }
    });

    // ✅ Request event'leri
    this.connection.on("RequestsLoaded", (requests, requestsCount) => {
        console.log(`📮 Friend requests received: ${requestsCount}`);
        if (window.dotNetObjectRef) {
            if (requestsCount > 0) {
                window.dotNetObjectRef.invokeMethodAsync("HandleGetRequests", requests, requestsCount)
                    .catch(error => console.error("❌ HandleGetRequests error:", error));
            }
        } else {
            console.warn("❌ dotNetObjectRef is null in RequestsLoaded");
        }
    });

    // ✅ Request removal event
    this.connection.on("RequestRemoved", (fromUserId) => {
        console.log(`🗑️ Request removed by user: ${fromUserId}`);
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleRequestRemoved', fromUserId)
                .catch(error => console.error("❌ HandleRequestRemoved error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in RequestRemoved");
        }
    });

    // ✅ Conference notification events(P2P)
    this.connection.on("ReceiveConferenceNotification", (roomId, starterUserId) => {
        console.log("📢 Conference notification:", {
            roomId: roomId,
            starter: starterUserId
        });
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleConferenceNotification', roomId, starterUserId)
                .catch(error => console.error("❌ HandleConferenceNotification error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in ReceiveConferenceNotification");
        }
    });
    this.connection.on("ReceiveP2pEndNotification", () => {

        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleP2PConferenceEnded')
                .catch(error => console.error("❌ HandleP2PConferenceEnded error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in HandleP2PConferenceEnded");
        }
    });
//GROUP CONFERENCE EVENTS
    this.connection.on("ReceiveGroupConferenceNotification", (roomId, starterId, groupId) => {
        console.log(`📞 Konferans bildirimi:`, { roomId, starterId, groupId });

        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleGroupConferenceStarted', roomId, starterId,groupId)
                .catch(error => console.error("❌ HandleConferenceNotification error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in ReceiveConferenceNotification");
        }
    });

    // ✅ User joined conference event
    this.connection.on("ReceiveUserJoined", (groupId, userId) => {
        console.log("👤 User joined conference:", {
            user: userId,
            group: groupId
        });
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleUserJoined', groupId, userId)
                .catch(error => console.error("❌ HandleUserJoined error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in ReceiveUserJoined");
        }
    });

    // ✅ User left conference event
    this.connection.on("ReceiveUserLeft", (roomId, userId) => {
        console.log("🚪 User left conference:", {
            user: userId,
            group: groupId
        });
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleUserLeft', roomId, userId)
                .catch(error => console.error("❌ HandleUserLeft error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in ReceiveUserLeft");
        }
    });

    // ✅ Conference ended event(GROUP)
    this.connection.on("ReceiveConferenceEnded", (groupId) => {
        console.log("🏁 Conference ended:", {
            group: groupId,
        });
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleGroupConferenceEnded', groupId)
                .catch(error => console.error("❌ HandleGroupConferenceEnded error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in ReceiveConferenceEnded");
        }
    });

    // ✅ Grup bilgisi güncellendiğinde (admin değişikliği, üye ekleme, vs)
    this.connection.on("ReceiveGroupUpdated", (groupId) => {
        console.log("📡 ReceiveGroupUpdated alındı - GroupId:", groupId);
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleGroupInfoUpdated', groupId)
                .catch(error => console.error("❌ HandleGroupInfoUpdated error:", error));
        } else {
            console.warn("❌ is null in HandleGroupInfoUpdated");
        }
    });

    // ✅ YENİ: Grup oluşturulduğunda
    this.connection.on("ReceiveGroupCreated", (groupId) => {
        console.log("🆕 ReceiveGroupCreated alındı - GroupId:", groupId);

        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleGroupInfoUpdated', groupId)
                .catch(error => console.error("❌ HandleGroupConferenceEnded error:", error));
        }  else {
            console.warn("❌is null in HandleGroupInfoUpdated");
        }
    });
    // ✅ YENİ: Kullanıcı gruptan ayrıldı/atıldı
    this.connection.on("ReceiveUserLeftGroup", (groupId, userId) => {
        console.log("🚪 ReceiveUserLeftGroup alındı - GroupId:", groupId, "UserId:", userId);

        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleGroupInfoUpdated', groupId)
                .catch(err => console.error("HandleGroupInfoUpdated invoke error:", err));
        }
    });

    // ✅ YENİ: Grup silindi
    this.connection.on("ReceiveGroupDeleted", (groupId) => {
        console.log("🗑️ ReceiveGroupDeleted alındı - GroupId:", groupId);

        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleGroupInfoUpdated', groupId)
                .catch(err => console.error("HandleGroupInfoUpdated invoke error:", err));
        }
    });

    this.connection.on("FriendListChanged", () => {
        console.log("👥 Friend list change detected!");
        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleFriendListChanged');
        }
    });
    this.connection.on("ReceiveUserInfoUpdated", (data) => {
        // Backend 'new { userId = userId }' gönderdiği için data.userId olarak okumalıyız
        const updatedId = (typeof data === 'object') ? data.userId : data;

        console.log("📡 SignalR: ReceiveUserInfoUpdated received for:", updatedId);

        if (window.dotNetObjectRef) {
            window.dotNetObjectRef.invokeMethodAsync('HandleUserInfoUpdated', updatedId)
                .catch(error => console.error("❌ HandleUserInfoUpdated error:", error));
        } else {
            console.warn("❌ dotNetObjectRef is null in HandleUserInfoUpdated");
        }
    });

    // ✅ Connection state event (isteğe bağlı)
    this.connection.on("ConnectionStateChanged", (state) => {
        console.log(`🔌 Connection state changed: ${state}`);
        this.isConnected = state === "Connected";
    });

    console.log("✅ All SignalR event listeners configured successfully");
};

// ✅ Event temizleme fonksiyonu
SignalRManager.prototype.clearAllEvents = function () {
    if (!this.connection) {
        console.log("⚠️ No connection to clear events from");
        return;
    }

    try {
        // ✅ Tüm event'leri temizle
        this.connection.off("ReceiveMessage");
        this.connection.off("FriendInfo");
        this.connection.off("MyInfo");
        this.connection.off("OnlineUsersList");
        this.connection.off("UnreadNotificationsLoaded");
        this.connection.off("RequestsLoaded");
        this.connection.off("RequestRemoved");
        this.connection.off("ReceiveConferenceNotification");
        this.connection.off("ReceiveGroupConferenceNotification"); // ✅ Eklendi
        this.connection.off("ReceiveUserJoined");
        this.connection.off("ReceiveUserLeft");
        this.connection.off("ReceiveConferenceEnded");
        this.connection.off("ConnectionStateChanged");
        this.connection.off("ReceiveGroupUpdated");
        this.connection.off("ReceiveGroupCreated"); // ✅ YENİ
        this.connection.off("ReceiveP2pEndNotification");
        this.connection.off("HandleGroupInfoUpdated");
        this.connection.off("ReceiveUserLeftGroup");
        this.connection.off("ReceiveGroupDeleted");



        console.log("🧹 All SignalR events cleared successfully");
    } catch (error) {
        console.warn("⚠️ Error clearing SignalR events:", error);
    }
};

// ✅ Event durumunu kontrol etme fonksiyonu (debug için)
SignalRManager.prototype.getEventStatus = function () {
    if (!this.connection) {
        return { status: "No connection", events: [] };
    }

    // SignalR connection'da kayıtlı event'leri kontrol etmek için
    return {
        status: "Connected",
        connectionState: this.connection.state,
        hasEvents: this.connection._callbacks ? Object.keys(this.connection._callbacks).length : 0
    };
};