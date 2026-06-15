using Domain.Entities;
using Domain.Enums;
using Domain.Interfaces;
using Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace Infrastructure.Services
{
    public class NotificationService : INotificationService
    {
        private readonly IDbContextFactory<ApplicationDbContext> _contextFactory;
        private readonly IMemoryCache _cache;
        // ❌ ICacheService'i kaldırın - döngüsel bağımlılık yaratıyor

        public NotificationService(IDbContextFactory<ApplicationDbContext> contextFactory, IMemoryCache cache)
        {
            _contextFactory = contextFactory;
            _cache = cache;
            // ❌ _cacheService'i kaldırın
        }

        public async Task<bool> SaveNotificationAsync(
          Guid toUserId,
          Guid fromUserId,
          NotificationType type,
          NotificationPriority priority)
        {
            try
            {
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

                using var context = _contextFactory.CreateDbContext();
                context.Notifications.Add(notification);
                var result = await context.SaveChangesAsync();

                if (result > 0)
                {
                    Console.WriteLine($"💾 Notification saved: {fromUserId} -> {toUserId}, Type: {type}");

                    // ✅ Cache'i direkt burada güncelle
                    await AddNotificationToCacheDirectly(notification);
                    Console.WriteLine($"🧠 Notification cache'e eklendi: {type}");

                    return true;
                }

                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ SaveNotificationAsync error: {ex.Message}");
                return false;
            }
        }

        // ✅ Cache güncelleme metodunu buraya taşı
        private async Task AddNotificationToCacheDirectly(Notification notification)
        {
            try
            {
                // ✅ FromUser relation'ını yükle
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

                // ✅ FromUser'ı olan notification'ı ekle
                cachedNotifications.Insert(0, notificationWithUser);

                if (cachedNotifications.Count > 50)
                {
                    cachedNotifications = cachedNotifications.Take(50).ToList();
                }

                var cacheOptions = new MemoryCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30),
                    SlidingExpiration = TimeSpan.FromMinutes(10),
                    Priority = CacheItemPriority.Normal
                };

                _cache.Set(cacheKey, cachedNotifications, cacheOptions);
                _cache.Remove(countCacheKey);

                Console.WriteLine($"Cache'e notification eklendi! UserId: {notification.UserId}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ AddNotificationToCacheDirectly error: {ex.Message}");
            }
        }

        public async Task<bool> MarkMultipleAsReadInDbAsync(List<Guid> notificationIds)
        {
            try
            {
                if (!notificationIds.Any()) return true;

                using var context = _contextFactory.CreateDbContext();

                var notifications = await context.Notifications
                    .Where(n => notificationIds.Contains(n.Id))
                    .ToListAsync();

                if (!notifications.Any()) return false;

                foreach (var notification in notifications)
                {
                    notification.IsRead = true;
                }

                var result = await context.SaveChangesAsync();

                if (result > 0)
                {
                    Console.WriteLine($"✅ DB'de toplu okundu işaretlemesi: {notifications.Count} notification");
                    return true;
                }

                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ MarkMultipleAsReadInDbAsync error: {ex.Message}");
                return false;
            }
        }

        // Diğer metodlar aynı kalır
        public async Task<List<Notification>> GetUserNotificationsAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            var dbNotifications = await context.Notifications
                .Include(n => n.FromUser)
                .Where(n => n.UserId == userId && n.IsActive)
                .OrderByDescending(n => n.CreatedAt)
                .Take(50)
                .ToListAsync();
            return dbNotifications;
        }

        public async Task<List<Request>> GetUserRequestsAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            var dbrequests = await context.Requests
                .Include(r => r.Sender)
                .Where(n => n.ReceiverId == userId)
                .OrderByDescending(n => n.SentAt)
                .Take(50)
                .ToListAsync();
            return dbrequests;
        }

        public async Task<int> GetUnreadNotificationCountAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            var count = await context.Notifications
                .CountAsync(n => n.UserId == userId && !n.IsRead && n.IsActive);
            return count;
        }

        public async Task<int> GetRequestCountAsync(Guid userId)
        {
            using var context = _contextFactory.CreateDbContext();
            var count = await context.Requests
                .CountAsync(n => n.ReceiverId == userId);
            return count;
        }

        // NotificationService.cs içine
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