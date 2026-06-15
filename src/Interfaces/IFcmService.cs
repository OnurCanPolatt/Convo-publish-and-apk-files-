namespace Domain.Interfaces
{
    public interface IFcmService
    {
        Task SendNotificationAsync(Guid userId, string title, string body, Guid? senderId = null, bool isGroup = false,
            string? targetName = null, string notificationType = "P2P_CHAT");
        Task SendNotificationToTokenAsync(string token, string title, string body, Guid? senderId = null,
            bool isGroup = false, string? targetName = null, string notificationType = "P2P_CHAT");
        Task SendVideoCallNotificationAsync(Guid userId, string callerName, string roomId, Guid callerId,
            bool isGroup = false, Guid? groupId = null, string? groupName = null
        );

        
    }
}