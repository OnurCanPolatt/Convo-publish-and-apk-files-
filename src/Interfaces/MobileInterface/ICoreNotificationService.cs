using Domain.Entities;
using Domain.Enums;

namespace Domain.Interfaces.MobileInterface;

public interface ICoreNotificationService
{
    // Temel Kayıt ve Güncelleme
    Task<bool> SaveNotificationAsync(Guid toUserId, Guid fromUserId, NotificationType type, NotificationPriority priority);
    Task<bool> MarkMultipleAsReadInDbAsync(List<Guid> notificationIds);
        
    // Mobil Özel (Flutter için DTO/Anonim Nesne döner)
    Task<(List<object> Notifications, int UnreadCount)> GetUserNotificationsForMobileAsync(Guid userId,int skip);
        
    // Ham Veri ve Sayaçlar
    Task<List<Request>> GetUserRequestsAsync(Guid userId);
    Task<int> GetUnreadNotificationCountAsync(Guid userId);
    Task<int> GetRequestCountAsync(Guid userId);
    Task SoftDeleteNotificationsAsync(List<Guid> notificationIds);
    Task SoftDeleteAllNotificationsAsync(Guid userId);
}