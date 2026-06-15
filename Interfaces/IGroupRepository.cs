using Convo.Domain.Entities;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Convo.Application.Common.Interfaces
{
    public interface IGroupRepository
    {
        Task<ChatGroup?> GetByIdAsync(int id);
        Task<int> AddAsync(ChatGroup group);
        Task UpdateAsync(ChatGroup group);
        Task DeleteAsync(int id);
        Task<List<ChatGroup>> GetUserGroupsAsync(Guid userId);

        // Member operations
        Task AddMemberAsync(GroupMember member);
        Task<GroupMember?> GetMemberAsync(int groupId, Guid userId);
        Task<List<GroupMember>> GetGroupMembersAsync(int groupId);
        Task RemoveMemberAsync(int groupId, Guid userId);
        Task<bool> IsGroupMemberAsync(int groupId, Guid userId);
        Task<bool> IsGroupAdminAsync(int groupId, Guid userId);

        // Message operations
        Task<int> AddMessageAsync(GroupMessage message);
        Task<List<GroupMessage>> GetMessagesAsync(int groupId, int count = 50);
    }
}