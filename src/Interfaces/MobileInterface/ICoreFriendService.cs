using Domain.Entities;

namespace Domain.Interfaces.MobileInterface;

public interface ICoreFriendService
{
    // Temel DB İşlemleri
    Task<bool> SendFriendRequest(Guid friendId);
    Task<bool> AcceptFriendRequest(Guid friendId);
    Task<bool> RejectFriendRequest(Guid friendId);
    Task<bool> RemoveFriendRequest(Guid friendId);
    Task<bool> RemoveFriend(Guid friendId);

    // Mobil Özel Veri Çekme (Flutter için anonim nesne döner)
    Task<List<object>> GetFriendRequestsForMobile(Guid currentUserId);
    Task<int> CalculateStatus(Guid userId, Guid targetId);
        
    // Standart Entity Listeleri
    Task<List<Friend>> GetMyFriends();
    Task<List<Friend>> GetMyFriendsWithoutNotDeleted();
        
    // Chat Gizleme
    Task HidePrivateChatAsync(Guid friendId, Guid currentUserId);
    Task<bool> UnhidePrivateChatAsync(Guid friendId, Guid currentUserId);
}