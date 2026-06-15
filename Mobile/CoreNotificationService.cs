using Domain.Entities;
using Domain.Enums;
using Domain.Interfaces.MobileInterface;
using Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory; // ✅ Webin cache'i için gerekli

namespace Infrastructure.Services.Mobile
{
    public class CoreNotificationService : ICoreNotificationService
    {
        private readonly IDbContextFactory<ApplicationDbContext> _contextFactory;
        private readonly IMemoryCache _cache; // ✅ Webin kullandığı cache yapısı

        public CoreNotificationService(IDbContextFactory<ApplicationDbContext> _factory, IMemoryCache cache)
        {
            _contextFactory = _factory;
            _cache = cache;
        }

        public async Task<bool> SaveNotificationAsync(Guid toUserId, Guid fromUserId, NotificationType type, NotificationPriority priority)
        {
            try
            {
                using var context = _contextFactory.CreateDbContext();
                var notification = new Notification
                {
                    Id = Guid.NewGuid(),
                    UserId = toUserId,
                    FromUserId = fromUserId,
                    Type = type,
                    Priority = priority,
                    IsActive = true,
                    IsRead = false,
                    CreatedAt = DateTime.UtcNow
                };

                context.Notifications.Add(notification);
                var saved = await context.SaveChangesAsync() > 0;

                if (saved)
                {
                    // ✅ KRİTİK: Webin bildirim panelindeki "8+" gibi sayıları ve listeyi cache'den temizle/güncelle
                    await AddNotificationToCacheForWeb(notification);
                    return true;
                }
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ SaveNotificationAsync hatası: {ex.Message}");
                return false;
            }
        }

        private async Task AddNotificationToCacheForWeb(Notification notification)
        {
            try
            {
                using var context = _contextFactory.CreateDbContext();
                var notificationWithUser = await context.Notifications
                    .Include(n => n.FromUser)
                    .FirstOrDefaultAsync(n => n.Id == notification.Id);

                if (notificationWithUser == null) return;

                var cacheKey = $"notifications:{notification.UserId}";
                var countCacheKey = $"unread_count:{notification.UserId}";

                var cachedNotifications = new List<Notification>();
                if (_cache.TryGetValue(cacheKey, out List<Notification> existing))
                {
                    cachedNotifications = existing ?? new List<Notification>();
                }

                cachedNotifications.Insert(0, notificationWithUser);
                if (cachedNotifications.Count > 50) cachedNotifications = cachedNotifications.Take(50).ToList();

                var cacheOptions = new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30),
                    SlidingExpiration = TimeSpan.FromMinutes(10)
                };

                _cache.Set(cacheKey, cachedNotifications, cacheOptions);
                _cache.Remove(countCacheKey); // Sayacı sıfırla ki Web tekrar DB'den taze sayıyı çeksin
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Web Cache Güncelleme Hatası: {ex.Message}");
            }
        }

        public async Task<(List<object> Notifications, int UnreadCount)> GetUserNotificationsForMobileAsync(Guid userId,int skip=0)
        {
            using var context = _contextFactory.CreateDbContext();

            // 1. Okunmamış sayısını (Badge için) hızlıca alalım
            var unreadCount = await context.Notifications
                .CountAsync(n => n.UserId == userId && n.IsActive && !n.IsRead);

            // 2. Son 50 bildirimi detaylarıyla alalım
            var notifications = await context.Notifications
                .Include(n => n.FromUser) // Gönderen bilgisini Joinle
                .Where(n => n.UserId == userId && n.IsActive)
                .OrderByDescending(n => n.CreatedAt)
                .Skip(skip)
                .Take(20)
                .Select(n => new {
                    id = n.Id,
                    senderId = n.FromUserId,
                    senderName = n.FromUser.UserName, // Bilinmeyen kullanıcıyı çözen satır
                    senderImageUrl = "", // Eğer profil fotoğrafı tablon varsa buraya ekleyebilirsin
                    type = (int)n.Type,
                    message = GetNotificationMessage(n.Type),
                    date = n.CreatedAt.ToUniversalTime().ToString("O"),
                    isRead = n.IsRead
                })
                .Cast<object>()
                .ToListAsync();

            return (notifications, unreadCount);
        }

        private static string GetNotificationMessage(NotificationType type)
        {
            return type switch
            {
                NotificationType.FriendRequest         => "size bir arkadaşlık isteği gönderdi.",
                NotificationType.FriendRequestAccepted => "arkadaşlık isteğinizi kabul etti.",
                NotificationType.FriendRequestReject   => "arkadaşlık isteğinizi reddetti.",
                NotificationType.FriendRemoved         => "sizi arkadaşlıktan çıkardı.",
                NotificationType.FriendRequestRemoved  => "arkadaşlık isteğini geri çekti.",
                _                                      => "yeni bir bildirim gönderdi."
            };
        }

        public async Task<bool> MarkMultipleAsReadInDbAsync(List<Guid> notificationIds)
        {
            using var context = _contextFactory.CreateDbContext();
            var notifications = await context.Notifications.Where(n => notificationIds.Contains(n.Id)).ToListAsync();
            foreach (var n in notifications) n.IsRead = true;
            return await context.SaveChangesAsync() > 0;
        }

        public async Task<List<Notification>> GetUserNotificationsAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            return await context.Notifications.Include(n => n.FromUser).Where(n => n.UserId == userId && n.IsActive).OrderByDescending(n => n.CreatedAt).Take(50).ToListAsync();
        }

        public async Task<List<Request>> GetUserRequestsAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            return await context.Requests.Include(r => r.Sender).Where(n => n.ReceiverId == userId).OrderByDescending(n => n.SentAt).Take(50).ToListAsync();
        }

        public async Task<int> GetUnreadNotificationCountAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            return await context.Notifications.CountAsync(n => n.UserId == userId && !n.IsRead && n.IsActive);
        }

        public async Task<int> GetRequestCountAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            return await context.Requests.CountAsync(n => n.ReceiverId == userId);
        }
        public async Task SoftDeleteNotificationsAsync(List<Guid> notificationIds)
        {
            using var context = _contextFactory.CreateDbContext();
    
            // Verilen ID listesindeki bildirimleri bul ve IsActive bayrağını false çek
            await context.Notifications
                .Where(n => notificationIds.Contains(n.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(n => n.IsActive, false));
        }

        public async Task SoftDeleteAllNotificationsAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
    
            // Kullanıcının tüm aktif bildirimlerini pasif yap
            await context.Notifications
                .Where(n => n.UserId == userId && n.IsActive)
                .ExecuteUpdateAsync(s => s.SetProperty(n => n.IsActive, false));
        }
    }
}