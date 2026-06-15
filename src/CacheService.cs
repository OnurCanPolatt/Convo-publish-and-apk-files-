using Domain.Entities;
using Domain.Interfaces;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace Infrastructure.Services
{
    public class CacheService : ICacheService
    {
        private readonly IMemoryCache _cache; // 🧠 Hafıza kutusu
        private readonly INotificationService _notificationService; // 📝 DB servisi
        private readonly ILogger<CacheService> _logger; // 📊 Log tutma
        private readonly IMessageService _messageService;
        
        // 🕒 Cache ne kadar süre duracak?
        private readonly TimeSpan _cacheExpiration = TimeSpan.FromMinutes(30); // 30 dakika

        public CacheService(
            IMemoryCache cache,
            INotificationService notificationService,
            IMessageService messageService,
            ILogger<CacheService> logger)
        {
            _cache = cache;
            _notificationService = notificationService;
            _messageService = messageService;
            _logger = logger;
        }
        // 🚀 1. Tüm notification'ları DB'den al ve cache'e yükle
        public async Task LoadAllNotificationsFromDbAsync()
        {
            try
            {
                _logger.LogInformation("Tüm notification'lar cache'e yükleniyor...");

                // Şimdilik bu metodu boş bırakıyoruz
                // Çünkü kullanıcı bazında lazy loading yapacağız

                _logger.LogInformation("Cache yükleme tamamlandı!");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Cache yükleme hatası!");
            }
        }
        private string GetCacheKey(Guid userId1, Guid userId2)
        {
            var minId = userId1.CompareTo(userId2) < 0 ? userId1 : userId2;
            var maxId = userId1.CompareTo(userId2) < 0 ? userId2 : userId1;
            return $"messages:{minId}-{maxId}";
        }
        #region Private messages cache
        public async Task<List<Message>> LoadUserMessagesAsync(Guid senderId,Guid receiverId)
        {
            var cacheKey = GetCacheKey(senderId, receiverId); try
            {
                // 🔍 1. ÖNCE CACHE'E BAK
                if (_cache.TryGetValue(cacheKey, out List<Message> cachedMessages))
                {
                    _logger.LogInformation($"Cache HIT! UserId: {senderId}");
                    // ✅ EN ESKİDEN YENİYE SIRALA (SentAt) - En yeni mesaj EN AŞAĞIDA
                    return cachedMessages?.OrderBy(m => m.SentAt).ToList() ?? new List<Message>();
                }

                // 🏃‍♂️ 2. CACHE'DE YOK - DB'DEN AL
                _logger.LogInformation($"Cache MISS! DB'den alınıyor... UserId: {senderId}");

                var dbMessages = await _messageService.GetMessagesAsync(senderId,receiverId);
                //get dbMessages distinct by message.id
                dbMessages = dbMessages.GroupBy(m => m.Id).Select(g => g.First()).ToList();

                // ✅ EN ESKİDEN YENİYE SIRALA (SentAt) - En yeni mesaj EN AŞAĞIDA
                dbMessages = dbMessages.OrderBy(m => m.SentAt).ToList();

                // 🧠 3. CACHE'E KAYDET
                var cacheOptions = new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = _cacheExpiration, // 30 dakika sonra sil
                    SlidingExpiration = TimeSpan.FromMinutes(10), // 10 dakika kullanılmazsa sil
                    Priority = CacheItemPriority.Normal
                };

                _cache.Set(cacheKey, dbMessages, cacheOptions);
                _logger.LogInformation($"Cache'e kaydedildi! UserId: {senderId}, Count: {dbMessages.Count}");

                return dbMessages;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"GetUserNotifications hatası! UserId: {senderId}");
                return new List<Message>(); // Hata durumunda boş liste dön
            }
        }
        // CacheService sınıfına eklenecek metod

        public async Task AddMessageToCacheAsync(Message message, Guid currentUserId, Guid otherUserId)
        {
            var cacheKey = GetCacheKey(currentUserId, otherUserId);
            try
            {
                if (_cache.TryGetValue(cacheKey, out List<Message> cachedMessages))
                {
                    // ID kontrolü yapıyoruz
                    var isDuplicate = cachedMessages.Any(m => m.Id == message.Id);

                    if (isDuplicate)
                    {
                        // MESAJ VARSA: Sadece log atıyoruz ve metodun geri kalanını (ekleme işlemini) yapmıyoruz.
                        // Ama Hub'a hata fırlatmıyoruz, böylece Hub mesajı dağıtmaya devam edebiliyor.
                        _logger.LogInformation($"[CACHE] P2P Message {message.Id} already in cache, skipping add.");
                    }
                    else 
                    {
                        cachedMessages.Add(message);
                        if (cachedMessages.Count > 100)
                        {
                            cachedMessages = cachedMessages.OrderByDescending(m => m.SentAt).Take(100).ToList();
                        }
                        _cache.Set(cacheKey, cachedMessages, _cacheExpiration);
                        _logger.LogInformation($"Message cached successfully. Cache size: {cachedMessages.Count}");
                    }
                }
                else
                {
                    _cache.Set(cacheKey, new List<Message> { message }, _cacheExpiration);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"AddMessageToCache error");
            }
        }
        // 🎯 2. Kullanıcının notification'larını getir (ANA METOD!)
        public async Task<List<Notification>> GetUserNotificationsAsync(Guid userId)
        {
            var cacheKey = $"notifications:{userId}"; // 🔑 Anahtar: "notifications:123-456-789"

            try
            {
                // 🔍 1. ÖNCE CACHE'E BAK
                if (_cache.TryGetValue(cacheKey, out List<Notification> cachedNotifications))
                {
                    _logger.LogInformation($"Cache HIT! UserId: {userId}");
                    return cachedNotifications ?? new List<Notification>();
                }

                // 🏃‍♂️ 2. CACHE'DE YOK - DB'DEN AL
                _logger.LogInformation($"Cache MISS! DB'den alınıyor... UserId: {userId}");

                var dbNotifications = await _notificationService.GetUserNotificationsAsync(userId);

                // 🧠 3. CACHE'E KAYDET
                var cacheOptions = new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = _cacheExpiration, // 30 dakika sonra sil
                    SlidingExpiration = TimeSpan.FromMinutes(10), // 10 dakika kullanılmazsa sil
                    Priority = CacheItemPriority.Normal
                };

                _cache.Set(cacheKey, dbNotifications, cacheOptions);
                _logger.LogInformation($"Cache'e kaydedildi! UserId: {userId}, Count: {dbNotifications.Count}");

                return dbNotifications;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"GetUserNotifications hatası! UserId: {userId}");
                return new List<Notification>(); // Hata durumunda boş liste dön
            }
        }
        public async Task<List<Request>> GetUserRequests(Guid userId)
        {
            var cacheKey = $"requests:{userId}"; // 🔑 Anahtar: "notifications:123-456-789"

            try
            {
                // 🔍 1. ÖNCE CACHE'E BAK
                if (_cache.TryGetValue(cacheKey, out List<Request> cachedRequests))
                {
                    _logger.LogInformation($"Cache HIT! UserId: {userId}");
                    return cachedRequests ?? new List<Request>();
                }

                // 🏃‍♂️ 2. CACHE'DE YOK - DB'DEN AL
                _logger.LogInformation($"Cache MISS! Requests DB'den alınıyor... UserId: {userId}");

                var dbRequests = await _notificationService.GetUserRequestsAsync(userId);

                // 🧠 3. CACHE'E KAYDET
                var cacheOptions = new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = _cacheExpiration, // 30 dakika sonra sil
                    SlidingExpiration = TimeSpan.FromMinutes(10), // 10 dakika kullanılmazsa sil
                    Priority = CacheItemPriority.Normal
                };

                _cache.Set(cacheKey, dbRequests, cacheOptions);
                _logger.LogInformation($"Requests Cache'e kaydedildi! UserId: {userId}, Count: {dbRequests.Count}");

                return dbRequests;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"GetUserRequestsAsync hatası! UserId: {userId}");
                return new List<Request>(); // Hata durumunda boş liste dön
            }
        }

        // 📊 3. Okunmamış sayısını getir
        public async Task<int> GetUnreadCountAsync(Guid userId)
        {
            var cacheKey = $"unread_count:{userId}"; // 🔑 Anahtar: "unread_count:123-456-789"

            try
            {
                // Cache'de varsa dön
                if (_cache.TryGetValue(cacheKey, out int cachedCount))
                {
                    _logger.LogInformation($"Unread count cache HIT! UserId: {userId}");
                    return cachedCount;
                }

                // DB'den al
                var dbCount = await _notificationService.GetUnreadNotificationCountAsync(userId);

                // Cache'e at (15 dakika)
                _cache.Set(cacheKey, dbCount, TimeSpan.FromMinutes(15));
                _logger.LogInformation($"Unread count cache'e kaydedildi! UserId: {userId}, Count: {dbCount}");

                return dbCount;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"GetUnreadCount hatası! UserId: {userId}");
                return 0;
            }
        }

        // ➕ 4. Yeni notification cache'e ekle
        public async Task AddNotificationToCacheAsync(Notification notification)
        {
            var cacheKey = $"notifications:{notification.UserId}";
            var countCacheKey = $"unread_count:{notification.UserId}";

            try
            {
                // Mevcut cache'i al
                var cachedNotifications = new List<Notification>();
                if (_cache.TryGetValue(cacheKey, out List<Notification> existing))
                {
                    cachedNotifications = existing ?? new List<Notification>();
                }

                // Yeni notification'ı BAŞA ekle (en yeni üstte)
                cachedNotifications.Insert(0, notification);

                // 50'den fazlaysa eski olanları sil
                if (cachedNotifications.Count > 50)
                {
                    cachedNotifications = cachedNotifications.Take(50).ToList();
                }

                // Cache'i güncelle
                _cache.Set(cacheKey, cachedNotifications, _cacheExpiration);

                // Unread count'u da temizle (yeniden hesaplanacak)
                _cache.Remove(countCacheKey);

                _logger.LogInformation($"Notification cache'e eklendi! UserId: {notification.UserId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"AddNotificationToCache hatası! UserId: {notification.UserId}");
            }
        }

        // ✅ 5. Notification'ı okundu olarak işaretle
        // Toplu mark as read için cache metodu
        public async Task MarkMultipleAsReadInCacheAsync(Guid userId, List<Guid> notificationIds)
        {
            var cacheKey = $"notifications:{userId}";
            var countCacheKey = $"unread_count:{userId}";

            try
            {
                if (_cache.TryGetValue(cacheKey, out List<Notification> cachedNotifications))
                {
                    // Cache'deki notification'ları toplu güncelle
                    foreach (var notification in cachedNotifications.Where(n => notificationIds.Contains(n.Id)))
                    {
                        notification.IsRead = true;
                    }

                    _cache.Set(cacheKey, cachedNotifications, _cacheExpiration);
                }

                // DB'yi background task olarak güncelle
                _ = Task.Run(async () =>
                {
                    try
                    {
                        await _notificationService.MarkMultipleAsReadInDbAsync(notificationIds);
                        _logger.LogInformation($"Background DB update completed for {notificationIds.Count} notifications");
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Background DB update failed");
                    }
                });

                // Count cache'ini temizle
                _cache.Remove(countCacheKey);

                _logger.LogInformation($"Toplu notification güncellendi! UserId: {userId}, Count: {notificationIds.Count}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"MarkMultipleAsReadInCache hatası! UserId: {userId}");
            }
        }

        // 🗑️ 6. Notification'ı cache'den sil
        public async Task RemoveNotificationFromCacheAsync(Guid userId, Guid notificationId)
        {
            var cacheKey = $"notifications:{userId}";
            var countCacheKey = $"unread_count:{userId}";

            try
            {
                if (_cache.TryGetValue(cacheKey, out List<Notification> cachedNotifications))
                {
                    cachedNotifications?.RemoveAll(n => n.Id == notificationId);
                    _cache.Set(cacheKey, cachedNotifications, _cacheExpiration);
                }

                // Unread count'u da temizle
                _cache.Remove(countCacheKey);

                _logger.LogInformation($"Notification cache'den silindi! UserId: {userId}, NotificationId: {notificationId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"RemoveNotificationFromCache hatası! UserId: {userId}");
            }
        }

        // 🧹 7. Kullanıcının tüm cache'ini temizle
        public async Task ClearUserCacheAsync(Guid userId)
        {
            try
            {
                var cacheKey = $"notifications:{userId}";
                var countCacheKey = $"unread_count:{userId}";

                _cache.Remove(cacheKey);
                _cache.Remove(countCacheKey);

                _logger.LogInformation($"Kullanıcı cache'i temizlendi! UserId: {userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"ClearUserCache hatası! UserId: {userId}");
            }
        }

        // 🧹 8. Tüm cache'i temizle
        public async Task ClearAllCacheAsync()
        {
            try
            {
                // MemoryCache'de tüm key'leri silmenin direkt yolu yok
                // Bu yüzden servis restart gerekir

                _logger.LogInformation("Tüm cache temizleme isteği alındı - servis restart gerekli");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ClearAllCache hatası!");
            }
        }
        public async Task<(List<Request> requests, int count)> InvalidateRequestsCacheAsync(Guid userId)
        {
            var cacheKey = $"requests:{userId}";
            try
            {
                // Cache'i temizle
                _cache.Remove(cacheKey);

                // Fresh data al ve cache'e koy
                var freshRequests = await _notificationService.GetUserRequestsAsync(userId);

                var cacheOptions = new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = _cacheExpiration,
                    SlidingExpiration = TimeSpan.FromMinutes(10),
                    Priority = CacheItemPriority.Normal
                };

                _cache.Set(cacheKey, freshRequests, cacheOptions);
                _logger.LogInformation($"Requests cache yenilendi! UserId: {userId}, Count: {freshRequests.Count}");
                return (freshRequests, freshRequests.Count);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"InvalidateRequestsCache hatası! UserId: {userId}");
                return (new List<Request>(), 0);
            }
        }
        public async Task RemoveRequestFromCacheAsync(Guid userId, Guid fromUserId)
        {
            var cacheKey = $"requests:{userId}";
            try
            {
                if (_cache.TryGetValue(cacheKey, out List<Request> cachedRequests))
                {
                    // SenderId'ye göre request'i bul ve sil
                    cachedRequests?.RemoveAll(r => r.SenderId == fromUserId);
                    _cache.Set(cacheKey, cachedRequests, _cacheExpiration);
                    _logger.LogInformation($"Request cache'den silindi! UserId: {userId}, FromUserId: {fromUserId}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"RemoveRequestFromCache hatası! UserId: {userId}");
            }
        }
        // CacheService.cs içine ekleyin
        public async Task RemoveNotificationsFromCacheAsync(Guid userId, List<Guid> notificationIds)
        {
            var cacheKey = $"notifications:{userId}";
            try
            {
                if (_cache.TryGetValue(cacheKey, out List<Notification> cachedNotifications))
                {
                    // Cache'den bu ID'leri çıkar (veya IsActive = false yapıp filtrele)
                    cachedNotifications.RemoveAll(n => notificationIds.Contains(n.Id));
                    _cache.Set(cacheKey, cachedNotifications, _cacheExpiration);
                }
        
                // DB'yi arka planda güncelle (UI'ı bekletme)
                _ = Task.Run(async () => await _notificationService.SoftDeleteNotificationsAsync(notificationIds));
        
                _cache.Remove($"unread_count:{userId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "RemoveNotificationsFromCache hatası");
            }
        }

        public async Task ClearAllNotificationsFromCacheAsync(Guid userId)
        {
            try
            {
                _cache.Remove($"notifications:{userId}");
                _cache.Remove($"unread_count:{userId}");
        
                // DB'yi arka planda temizle
                _ = Task.Run(async () => await _notificationService.SoftDeleteAllNotificationsAsync(userId));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ClearAllNotificationsFromCache hatası");
            }
        }
#endregion
        #region Group Messages Cache

        public async Task<List<Message>> LoadGroupMessagesAsync(Guid groupId)
        {
            var cacheKey = $"group_messages:{groupId}";

            try
            {
                // 🔍 1. ÖNCE CACHE'E BAK
                if (_cache.TryGetValue(cacheKey, out List<Message> cachedMessages))
                {
                    _logger.LogInformation($"Group messages cache HIT! GroupId: {groupId}");
                    // ✅ EN ESKİDEN YENİYE SIRALA (SentAt) - En yeni mesaj EN AŞAĞIDA
                    return cachedMessages?.OrderBy(m => m.SentAt).ToList() ?? new List<Message>();
                }

                // 🏃‍♂️ 2. CACHE'DE YOK - DB'DEN AL
                _logger.LogInformation($"Group messages cache MISS! DB'den alınıyor... GroupId: {groupId}");

                var dbMessages = await _messageService.GetGroupMessagesAsync(groupId);

                // Duplike kontrolü (güvenlik için)
                dbMessages = dbMessages.GroupBy(m => m.Id).Select(g => g.First()).ToList();

                // ✅ EN ESKİDEN YENİYE SIRALA (SentAt) - En yeni mesaj EN AŞAĞIDA
                dbMessages = dbMessages.OrderBy(m => m.SentAt).ToList();

                // 🧠 3. CACHE'E KAYDET
                var cacheOptions = new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = _cacheExpiration, // 30 dakika sonra sil
                    SlidingExpiration = TimeSpan.FromMinutes(10), // 10 dakika kullanılmazsa sil
                    Priority = CacheItemPriority.Normal
                };

                _cache.Set(cacheKey, dbMessages, cacheOptions);
                _logger.LogInformation($"Group messages cache'e kaydedildi! GroupId: {groupId}, Count: {dbMessages.Count}");

                return dbMessages;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"LoadGroupMessages hatası! GroupId: {groupId}");
                return new List<Message>();
            }
        }

        public async Task AddGroupMessageToCacheAsync(Message message, Guid groupId)
        {
            var cacheKey = $"group_messages:{groupId}";
            try
            {
                if (_cache.TryGetValue(cacheKey, out List<Message> cachedMessages))
                {
                    var isDuplicate = cachedMessages.Any(m => m.Id == message.Id);

                    if (isDuplicate)
                    {
                        _logger.LogInformation($"[CACHE] Group Message {message.Id} already in cache, skipping add.");
                    }
                    else 
                    {
                        cachedMessages.Add(message);
                        if (cachedMessages.Count > 200)
                        {
                            cachedMessages = cachedMessages.OrderByDescending(m => m.SentAt).Take(200).ToList();
                        }
                        _cache.Set(cacheKey, cachedMessages, _cacheExpiration);
                        _logger.LogInformation($"Group message cached successfully. GroupId: {groupId}");
                    }
                }
                else
                {
                    _cache.Set(cacheKey, new List<Message> { message }, _cacheExpiration);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"AddGroupMessageToCache error. GroupId: {groupId}");
            }
        }

        public async Task ClearGroupCacheAsync(Guid groupId)
        {
            try
            {
                var cacheKey = $"group_messages:{groupId}";
                _cache.Remove(cacheKey);
                _logger.LogInformation($"Group cache temizlendi! GroupId: {groupId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"ClearGroupCache hatası! GroupId: {groupId}");
            }
        }

        #endregion
    }
}