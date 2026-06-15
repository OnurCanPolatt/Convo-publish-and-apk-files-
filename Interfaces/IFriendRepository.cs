using Convo.Domain.Entities;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Convo.Application.Common.Interfaces
{
    public interface IFriendRepository
    {
        Task<List<MyFriend>> GetAllFriendsAsync(Guid userId);
        Task<bool> AddFriendAsync(Guid userId, Guid friendId, string userName, string friendName);
        Task<bool> RemoveFriendAsync(Guid userId, Guid friendId);
        Task<bool> AreFriendsAsync(Guid userId, Guid friendId);
        Task SaveFileTransferAsync(PrivateMessage privateMessage);
    }
}