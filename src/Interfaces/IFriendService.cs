using Domain.Entities;
using Domain.Enums;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Interfaces
{
    public interface IFriendService
    {
        Task<bool> SendFriendRequest(Guid friendId);
        Task<bool> AcceptFriendRequest(Guid friendId);
        Task<bool> RemoveFriendRequest(Guid friendId);
        Task<bool> RejectFriendRequest(Guid friendId);

        Task<List<Request>> GetFriendRequests(Guid currentUserId);
        Task<List<Friend>> GetMyFriends();
        Task<List<Friend>> GetMyFriendsWithoutNotDeleted();
        Task<bool> RemoveFriend(Guid friendId);
        Task HidePrivateChatAsync(Guid friendId, Guid currentUserId);
        Task<bool> UnhidePrivateChatAsync(Guid friendId, Guid currentUserId);

    }

}
