using Domain.Entities;
using Domain.Enums;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;


namespace Domain.Interfaces
{
    public interface IGroupService
    {
        Task<bool> AddMembersToGroup(Guid groupId, List<Guid> memberIds);
        Task<bool> DeleteMemberFromGroup(Guid groupId, Guid memberId);
        Task<bool> AddRoleToMember(Guid groupId, Guid memberId, ChatRoomRole role);
        Task<bool> CreateGroup(ChatRoom chatRoom);
        Task<List<ChatRoom>> GetMyGroups(Guid currentUserId);
        Task<ChatRoom> GetGroupInfo(Guid groupId);
        Task<ChatRoom> GetFreshGroupInfo(Guid groupId);
        Task<ChatRoom> GetGroupInfoWithActiveMembers(Guid groupId);
        Task<bool> UpdateGroupInfo(Guid groupId, string name, string? description, string? imageUrl);
        Task<List<Guid>> GetGroupMemberIdsAsync(Guid groupId);
        Task<bool> UpdateMemberAdminStatus(Guid groupId, Guid memberId, bool isAdmin);
        Task<bool> LeaveGroup(Guid groupId, Guid userId);
        Task<bool> DeleteGroup(Guid groupId, Guid requestedByUserId);
        Task HideGroupChatAsync(Guid groupId, Guid userId);
        Task<bool> UnhideGroupChatAsync(Guid groupId, Guid userId);

    }
}
