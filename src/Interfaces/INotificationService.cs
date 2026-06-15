using Domain.Entities;
using Domain.Enums;
using System.Threading;

namespace Domain.Interfaces
{
    public interface INotificationService
    {
        // 📬 Bildirim kaydet (hem DB hem Cache - Fire-and-forget DB)
        Task<bool> SaveNotificationAsync(
          Guid toUserId,
          Guid fromUserId,
          NotificationType type,
          NotificationPriority priority     
      );
        Task<bool> MarkMultipleAsReadInDbAsync(List<Guid> notificationIds);
        // 📮 Kullanıcının tüm bildirimlerini getir (Cache first, fallback to DB)
        Task<List<Notification>> GetUserNotificationsAsync(Guid userId);
        Task<List<Request>> GetUserRequestsAsync(Guid userId);

        // 🔢 Okunmamış bildirim sayısı (Cache first, fallback to DB)
        Task<int> GetUnreadNotificationCountAsync(Guid userId);
        Task<int> GetRequestCountAsync(Guid userId);
        Task SoftDeleteNotificationsAsync(List<Guid> notificationIds);
        Task SoftDeleteAllNotificationsAsync(Guid userId);


    }
}