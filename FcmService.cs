using Domain.Interfaces;
using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

namespace Infrastructure.Services
{
    public class FcmService : IFcmService
    {
        private readonly IDeviceTokenService _deviceTokenService;
        private static bool _initialized = false;

        public FcmService(IDeviceTokenService deviceTokenService)
        {
            _deviceTokenService = deviceTokenService;
            InitializeFirebase();
        }

        private void InitializeFirebase()
        {
            if (_initialized) return;

            try
            {
                // Dosya adını ve yolunu kontrol ederek başlatıyoruz
                string credentialPath = "firebase-credentials.json";
                
                if (FirebaseApp.DefaultInstance == null)
                {
                    FirebaseApp.Create(new AppOptions
                    {
                        Credential = GoogleCredential.FromFile(credentialPath)
                    });
                    Console.WriteLine("✅ Firebase Admin SDK başarıyla başlatıldı");
                }
                _initialized = true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ Firebase başlatma hatası: {ex.Message}");
                _initialized = false; // Hata alırsak false kalsın ki tekrar denenebilsin
            }
        }

        // SendNotificationAsync metodunu şu şekilde revize et:
public async Task SendNotificationAsync(Guid userId, string title, string body, Guid? senderId = null, bool isGroup = false, string? targetName = null, string notificationType = "P2P_CHAT")
{
    try
    {
        var tokens = await _deviceTokenService.GetTokensByUserIdAsync(userId);
        if (tokens == null || tokens.Count == 0) return;

        foreach (var token in tokens)
        {
            // notificationType parametresini alt metoda pasla
            await SendNotificationToTokenAsync(token, title, body, senderId, isGroup, targetName, notificationType);
        }
    }
    catch (Exception ex) { Console.WriteLine($"❌ SendNotificationAsync hatası: {ex.Message}"); }
}

// SendNotificationToTokenAsync metodunu şu şekilde revize et:
public async Task SendNotificationToTokenAsync(string token, string title, string body, Guid? senderId = null, bool isGroup = false, string? targetName = null, string notificationType = "P2P_CHAT")
{
    try
    {
        var app = FirebaseApp.DefaultInstance ?? InitializeFirebaseInternal();
        var messaging = FirebaseMessaging.GetMessaging(app);

        string idValue = senderId.HasValue ? senderId.Value.ToString() : "";

        // 🚀 KRİTİK MANTIK: Eğer tip belirtilmemişse eski chat mantığını koru, 
        // ama dışarıdan bir tip (örn: FRIEND_NOTIFICATION) gelirse onu bas.
        string finalType = notificationType;
        if (finalType == "P2P_CHAT" && isGroup) finalType = "GROUP_CHAT";

        var message = new Message
        {
            Token = token,
            Notification = new Notification { Title = title, Body = body },
            Data = new Dictionary<string, string>()
            {
                { "type", finalType }, // 👈 Artik "FRIEND_NOTIFICATION" buraya gelebilecek
                { "id", idValue }, 
                { "name", targetName ?? "Convo" }, 
                { "click_action", "FLUTTER_NOTIFICATION_CLICK" }
            },
            Android = new AndroidConfig
            {
                Priority = Priority.High,
                Notification = new AndroidNotification 
                { 
                    Sound = "default",
                    ClickAction = "FLUTTER_NOTIFICATION_CLICK"
                }
            }
        };

        await messaging.SendAsync(message);
        Console.WriteLine($"✅ Push Gönderildi. Tip: {finalType}, Hedef: {targetName}");
    }
    catch (Exception ex) { Console.WriteLine($"❌ Push Hatası: {ex.Message}"); }
}

// Helper metod
        private FirebaseApp InitializeFirebaseInternal()
        {
            string credentialPath = "firebase-credentials.json";
            return FirebaseApp.Create(new AppOptions
            {
                Credential = GoogleCredential.FromFile(credentialPath)
            });
        }
        public async Task SendVideoCallNotificationAsync(
            Guid userId,
            string callerName,
            string roomId,
            Guid callerId,
            bool isGroup = false,
            Guid? groupId = null,
            string? groupName = null
        )
        {
            try
            {
                var tokens = await _deviceTokenService.GetTokensByUserIdAsync(userId);

                if (tokens == null || tokens.Count == 0)
                {
                    Console.WriteLine($"⚠️ Kullanıcı {userId} için FCM token bulunamadı, video call push gönderilemedi.");
                    return;
                }

                foreach (var token in tokens)
                {
                    await SendVideoCallNotificationToTokenAsync(
                        token,
                        callerName,
                        roomId,
                        callerId,
                        isGroup,
                        groupId,
                        groupName
                    );
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ SendVideoCallNotificationAsync hatası: {ex.Message}");
            }
        }
      private async Task SendVideoCallNotificationToTokenAsync(
      string token,
      string callerName,
      string roomId,
      Guid callerId,
      bool isGroup,
      Guid? groupId,
      string? groupName
  )
  {
      try
      {
          var app = FirebaseApp.DefaultInstance ?? InitializeFirebaseInternal();
          if (app == null) return;

          var messaging = FirebaseMessaging.GetMessaging(app);

          string title = isGroup ? (groupName ?? "Grup Araması") : callerName;
          string body = isGroup ? "Grup video konferansı başladı" : "Sizi arıyor...";

          var message = new Message
          {
              Token = token,
              Data = new Dictionary<string, string>()
              {
                  { "type", isGroup ? "GROUP_VIDEO_CALL" : "P2P_VIDEO_CALL" },
                  { "roomId", roomId },
                  { "starterId", callerId.ToString() },
                  { "starterName", callerName },
                  { "groupId", groupId?.ToString() ?? "" },
                  { "groupName", groupName ?? "" },
                  { "chatId", isGroup ? (groupId?.ToString() ?? "") : callerId.ToString() },
                  { "click_action", "FLUTTER_NOTIFICATION_CLICK" },
                  { "title", title },
                  { "body", body }
              },
              Android = new AndroidConfig
              {
                  Priority = Priority.High,
                  TimeToLive = TimeSpan.FromMinutes(5)

              }
          };


          string response = await messaging.SendAsync(message);
          Console.WriteLine($"✅ Video Call Push Gönderildi. Tip: {(isGroup ? "Grup" : "P2P")}, RoomId: {roomId}, Arayan: {callerName}");
      }
      catch (Exception ex)
      {
          Console.WriteLine($"❌ SendVideoCallNotificationToTokenAsync hatası: {ex.Message}");
      }
  }
    }
}