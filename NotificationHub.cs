using Infrastructure.Services;
using Microsoft.AspNetCore.SignalR;
using System.Collections.Concurrent;
using Domain.Interfaces;
using Domain.Interfaces.HubInterface;
using Microsoft.AspNetCore.Authorization;
using System.Threading;
using Domain.Interfaces.MobileInterface;

namespace Infrastructure.Hubs
{
    [Authorize]
    public partial class NotificationHub : Hub, IHubService
    {
        private readonly INotificationService _hubNotificationService;
        private readonly IFriendService _friendService;
        private readonly ICacheService _cache;
        private readonly ICoreNotificationService _mobileNotificationService;
        private readonly IFcmService _fcmService;
        private readonly IGroupService _groupService;
        private readonly IUserService _userService;
        private readonly ICacheService _cacheService;
        private readonly ICoreFriendService _coreFriendService;

        // ⚠️ YENİ: IHubContext için static field
        private static IHubContext<NotificationHub> _hubContext;

        private static readonly ConcurrentDictionary<string, HashSet<string>> _groupConnections = new();
        // UserId -> List<ConnectionId> mapping
        private static readonly ConcurrentDictionary<string, List<string>> _connectedUsers = new();

        // ✅ YENİ: Geçici disconnect takibi için grace period
        private static readonly ConcurrentDictionary<string, DateTime> _tempDisconnected = new();

        public NotificationHub(
            INotificationService hubNotificationService, 
            ICacheService cache, 
            IFriendService friendService,
            IHubContext<NotificationHub> hubContext, // 👈 YENİ PARAMETRE
            ICoreNotificationService mobileNotificationService,
            IFcmService fcmService,
            IGroupService groupService,
            IUserService userService,
            ICacheService cacheService,
            ICoreFriendService coreFriendService)
        {
            _hubNotificationService = hubNotificationService;
            _cache = cache;
            _friendService = friendService;
            _hubContext = hubContext; // 👈 Static field'a ata
            _mobileNotificationService=mobileNotificationService;
            _fcmService = fcmService;
            _groupService = groupService;
            _userService=userService;
            _cacheService = cacheService;
            _coreFriendService = coreFriendService;
        }

        public override async Task OnConnectedAsync()
        {
            Console.WriteLine($"✅ Yeni bağlantı: {Context.ConnectionId}");
            Console.WriteLine($"   🔐 User: {Context.User?.Identity?.Name ?? "Anonymous"}");
            Console.WriteLine($"   🔐 IsAuthenticated: {Context.User?.Identity?.IsAuthenticated}");
            await base.OnConnectedAsync();
        }

        public override async Task OnDisconnectedAsync(Exception exception)
        {
            var connectionId = Context.ConnectionId;
            string disconnectedUserId = null;

            // Bu connection ID'ye sahip user'ı bul ve connection'ı sil
            foreach (var user in _connectedUsers.ToList())
            {
                if (user.Value.Contains(connectionId))
                {
                    disconnectedUserId = user.Key;
                    user.Value.Remove(connectionId);

                    // ✅ Eğer user'ın hiç connection'ı kalmadıysa grace period başlat
                    if (!user.Value.Any())
                    {
                        // Dictionary'den kullanıcıyı sil
                        _connectedUsers.TryRemove(user.Key, out _);

                        // ✅ Grace period başlat - geçici olarak işaretle
                        _tempDisconnected.TryAdd(user.Key, DateTime.UtcNow);

                        Console.WriteLine($"⏰ User {user.Key} grace period başladı (10 saniye)");
                        
                        // ⚠️ DÜZELTİLDİ: Grace period'da listeyi güncelle
                        await BroadcastOnlineUsers();
                        
                        // ✅ 10 saniye sonra kontrol et
                        var userId = user.Key; // Closure için yerel değişken
                        _ = Task.Run(async () =>
                        {
                            await Task.Delay(10000); // 10 saniye bekle

                            // Hala bağlı değil ve temp listede varsa gerçekten offline yap
                            if (!_connectedUsers.ContainsKey(userId) &&
                                _tempDisconnected.TryRemove(userId, out _))
                            {
                                Console.WriteLine($"❌ User {userId} gerçekten offline oldu");

                                // ✅ DÜZELTİLDİ: IHubContext kullan
                                try
                                {
                                    await _hubContext.Clients.All.SendAsync("UserOffline", userId);
                                    Console.WriteLine($"📢 UserOffline sinyali gönderildi: {userId}");
                                    
                                    // BroadcastOnlineUsers da gönder
                                    var onlineUsers = _connectedUsers.Keys
                                        .Where(uid => !_tempDisconnected.ContainsKey(uid))
                                        .ToArray();
                                    await _hubContext.Clients.All.SendAsync("OnlineUsersList", onlineUsers);
                                    Console.WriteLine($"📢 OnlineUsersList güncellendi (grace period sonrası)");
                                }
                                catch (Exception ex)
                                {
                                    Console.WriteLine($"❌ UserOffline sinyal hatası: {ex.Message}");
                                }
                            }
                            else
                            {
                                Console.WriteLine($"✅ User {userId} geri bağlandı, offline gösterilmedi");
                            }
                        });
                    }
                    else
                    {
                        Console.WriteLine($"🔄 User {user.Key} connection {connectionId} disconnected. Kalan connections: {user.Value.Count}");
                        // ⚠️ DÜZELTİLDİ: Sadece connection sayısı azaldıysa broadcast gerekmiyor
                        // await BroadcastOnlineUsers(); // KALDIRILDI - Gereksiz broadcast
                    }

                    break;
                }
            }

            if (disconnectedUserId != null)
            {
                Console.WriteLine($"❌ User {disconnectedUserId} connection {connectionId} disconnected");
            }
            else
            {
                Console.WriteLine($"⚠️ Unknown connection {connectionId} disconnected");
            }

            await base.OnDisconnectedAsync(exception);
        }

        // ⚠️ DÜZELTİLDİ: RegisterUser metodu tamamen yeniden yazıldı
        public async Task RegisterUser(string userId)
        {
            var connectionId = Context.ConnectionId;
            Console.WriteLine($"🔍 RegisterUser çağrıldı - UserId: {userId}, ConnectionId: {connectionId}");

            // ✅ Grace period'dan çıkar - kullanıcı geri döndü!
            bool wasInGracePeriod = false;
            if (_tempDisconnected.TryRemove(userId, out var disconnectTime))
            {
                wasInGracePeriod = true;
                var offlineDuration = DateTime.UtcNow - disconnectTime;
                Console.WriteLine($"🎉 User {userId} geri döndü! Offline süresi: {offlineDuration.TotalSeconds:F1} saniye");
            }

            // ✅ Aynı connection zaten kayıtlı mı kontrol et
            var existingUserId = GetUserIdFromConnection(connectionId);
            if (existingUserId != "unknown" && existingUserId == userId)
            {
                Console.WriteLine($"⚠️ Connection {connectionId} zaten {userId} için kayıtlı");
                
                // ⚠️ DÜZELTİLDİ: Zaten kayıtlıysa bile online list'i gönder
                // Çünkü client yeniden bağlanmış olabilir (sayfa yenileme, ağ kesintisi)
                await BroadcastOnlineUsers();
                return;
            }

            // ⚠️ DÜZELTİLDİ: ÖNCE kullanıcıyı listeye ekle
            bool isNewConnection = false;
            _connectedUsers.AddOrUpdate(
                userId,
                new List<string> { connectionId }, // Yeni user ise liste oluştur
                (key, existingList) =>
                {
                    if (!existingList.Contains(connectionId))
                    {
                        existingList.Add(connectionId);
                        isNewConnection = existingList.Count == 1; // İlk connection ise
                        Console.WriteLine($"✅ Connection {connectionId} eklendi. Total connections: {existingList.Count}");
                    }
                    else
                    {
                        Console.WriteLine($"⚠️ Connection {connectionId} zaten listede var");
                    }
                    return existingList;
                });

            Console.WriteLine($"📊 User {userId} total connections: {_connectedUsers[userId].Count}");
            Console.WriteLine($"📊 All connections for {userId}: [{string.Join(", ", _connectedUsers[userId])}]");

            // ⚠️ DÜZELTİLDİ: HEMEN online durumunu broadcast et (notification'lardan ÖNCE)
            // Böylece diğer kullanıcılar hemen görür
            if (isNewConnection || wasInGracePeriod)
            {
                // Sadece yeni bağlantı veya grace period'dan dönüş varsa bildir
                await Clients.Others.SendAsync("UserOnline", userId);
                Console.WriteLine($"📢 UserOnline sinyali gönderildi: {userId}");
            }
            
            await BroadcastOnlineUsers();
            Console.WriteLine($"📢 OnlineUsersList broadcast edildi");

            // ⚠️ DÜZELTİLDİ: Notification bilgilerini al ve gönder (SONRA)
            // Bu uzun sürebilir, ama online durumu zaten gönderildi
            try
            {
                // ⚠️ DÜZELTİLDİ: Task.WhenAll ile paralel çalıştır (daha hızlı)
                var notificationTask = _hubNotificationService.GetUserNotificationsAsync(Guid.Parse(userId));
                var notificationCountTask = _hubNotificationService.GetUnreadNotificationCountAsync(Guid.Parse(userId));
                var requestsTask = _hubNotificationService.GetUserRequestsAsync(Guid.Parse(userId));
                var requestCountTask = _hubNotificationService.GetRequestCountAsync(Guid.Parse(userId));

                await Task.WhenAll(notificationTask, notificationCountTask, requestsTask, requestCountTask);

                var unReadNotify = notificationTask.Result;
                var unReadNotifyCount = notificationCountTask.Result;
                var requests = requestsTask.Result;
                var requestCount = requestCountTask.Result;

                if (unReadNotify != null && unReadNotifyCount != null && _connectedUsers.ContainsKey(userId))
                {
                    await SendUnreadNotificationsToUser(userId, unReadNotify, unReadNotifyCount);
                    Console.WriteLine($"📨 User {userId}'e {unReadNotifyCount} notification bilgisi gönderildi");
                }

                if (requests != null && requestCount != null && _connectedUsers.ContainsKey(userId))
                {
                    await SendRequestNotify(userId, requests, requestCount);
                    Console.WriteLine($"📨 User {userId}'e {requestCount} request bilgisi gönderildi");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Notification yükleme hatası: {ex.Message}");
                Console.WriteLine($"❌ Stack Trace: {ex.StackTrace}");
            }
        }

        // ⚠️ DÜZELTİLDİ: GetHubStatus metoduna daha fazla bilgi eklendi
        public async Task GetHubStatus()
        {
            var status = new
            {
                ConnectedUsers = _connectedUsers.ToDictionary(kv => kv.Key, kv => kv.Value.Count),
                TempDisconnected = _tempDisconnected.ToDictionary(kv => kv.Key, kv => (DateTime.UtcNow - kv.Value).TotalSeconds),
                ReallyOnlineUsers = GetReallyOnlineUsers(),
                TotalConnections = _connectedUsers.Values.Sum(list => list.Count),
                CurrentConnectionId = Context.ConnectionId,
                CurrentUserId = Context.User?.Identity?.Name ?? "Anonymous",
                IsAuthenticated = Context.User?.Identity?.IsAuthenticated ?? false
            };

            await Clients.Caller.SendAsync("HubStatus", status);
            Console.WriteLine($"📊 Hub Status requested by {Context.ConnectionId}");
            Console.WriteLine($"   Connected Users: {_connectedUsers.Count}");
            Console.WriteLine($"   Temp Disconnected: {_tempDisconnected.Count}");
            Console.WriteLine($"   Total Connections: {status.TotalConnections}");
        }

        // ⚠️ DÜZELTİLDİ: BroadcastOnlineUsers'a daha detaylı log eklendi
        public async Task BroadcastOnlineUsers()
        {
            var users = GetReallyOnlineUsers();
            
            Console.WriteLine($"📢 Broadcasting online users: [{string.Join(", ", users)}]");
            Console.WriteLine($"📊 Total: {users.Length} users online, {_tempDisconnected.Count} in grace period");
            
            await Clients.All.SendAsync("OnlineUsersList", users);
        }

        private string[] GetReallyOnlineUsers()
        {
            var onlineUsers = _connectedUsers.Keys
                .Where(userId => !_tempDisconnected.ContainsKey(userId))
                .ToArray();

            // ⚠️ DÜZELTİLDİ: Debug log eklendi
            Console.WriteLine($"🔍 GetReallyOnlineUsers: {onlineUsers.Length} users");
            foreach (var userId in onlineUsers)
            {
                Console.WriteLine($"   - {userId} ({_connectedUsers[userId].Count} connections)");
            }

            return onlineUsers;
        }

        // for mobile api
        public Task<string[]> GetReallyOnlineUsersListAsync()
        {
            return Task.FromResult(GetReallyOnlineUsers());
        }

        // ✅ Kullanıcının gerçekten online olup olmadığını kontrol et
        private bool IsUserReallyOnline(string userId)
        {
            return _connectedUsers.ContainsKey(userId) && !_tempDisconnected.ContainsKey(userId);
        }

        // Connection ID'den User ID bul
        private string GetUserIdFromConnection(string connectionId)
        {
            foreach (var user in _connectedUsers)
            {
                if (user.Value.Contains(connectionId))
                {
                    return user.Key;
                }
            }
            return "unknown";
        }

        // ✅ Periyodik temizlik - çok eski temp disconnected kayıtları sil
        static NotificationHub()
        {
            // Her 5 dakikada bir eski temp disconnected kayıtları temizle
            _ = Task.Run(async () =>
            {
                while (true)
                {
                    try
                    {
                        await Task.Delay(TimeSpan.FromMinutes(5));

                        var cutoff = DateTime.UtcNow.AddMinutes(-2); // 2 dakikadan eski kayıtları sil
                        var toRemove = _tempDisconnected
                            .Where(kv => kv.Value < cutoff)
                            .Select(kv => kv.Key)
                            .ToList();

                        foreach (var userId in toRemove)
                        {
                            if (_tempDisconnected.TryRemove(userId, out var disconnectTime))
                            {
                                Console.WriteLine($"🧹 Cleaned old temp disconnect: {userId} (offline for {(DateTime.UtcNow - disconnectTime).TotalMinutes:F1} min)");
                            }
                        }

                        if (toRemove.Any())
                        {
                            Console.WriteLine($"🧹 Cleaned {toRemove.Count} old temp disconnect records");
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"❌ Cleanup task error: {ex.Message}");
                    }
                }
            });
        }
    }
}