using Domain.Entities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Interfaces
{
    public interface ICacheService
    {
        // ✅ Notification cache işlemleri
        Task LoadAllNotificationsFromDbAsync();
        Task<List<Message>> LoadUserMessagesAsync(Guid senderId,Guid receiverId);
        Task<List<Notification>> GetUserNotificationsAsync(Guid userId);
        Task<List<Request>> GetUserRequests(Guid userId);
        Task<int> GetUnreadCountAsync(Guid userId);
        Task AddNotificationToCacheAsync(Notification notification);
        Task MarkMultipleAsReadInCacheAsync(Guid userId, List<Guid> notificationIds);
        Task RemoveNotificationFromCacheAsync(Guid userId, Guid notificationId);

        // ✅ Genel cache işlemleri
        Task ClearUserCacheAsync(Guid userId);
        Task ClearAllCacheAsync();
        Task RemoveRequestFromCacheAsync(Guid userId, Guid requestId);
        Task<(List<Request> requests, int count)> InvalidateRequestsCacheAsync(Guid userId);
        Task AddMessageToCacheAsync(Message message, Guid currentUserId, Guid otherUserId);
        Task<List<Message>> LoadGroupMessagesAsync(Guid groupId);
        Task AddGroupMessageToCacheAsync(Message message, Guid groupId);
        Task ClearGroupCacheAsync(Guid groupId);
        Task RemoveNotificationsFromCacheAsync(Guid userId, List<Guid> notificationIds);

        Task ClearAllNotificationsFromCacheAsync(Guid userId);

    }
}
