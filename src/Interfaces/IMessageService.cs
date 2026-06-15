using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Domain.Entities;
using Domain.Models.Dto;

namespace Domain.Interfaces
{
    public interface IMessageService
    {
        Task<bool> SaveMessage(Message message);
        Task<List<Message>> GetMessagesAsync(Guid senderId, Guid receiverId);
        Task<List<Message>> GetAllMyMessages(Guid senderId);
        Task<List<Message>> GetGroupMessagesAsync(Guid groupId);
        Task<List<ConversationListItemDto>> GetRecentConversationsAsync(Guid userId);
        //Task MarkAsReadAsync(Guid messageId); 
        //Task DeleteMessageAsync(Guid messageId);
        //Task<IEnumerable<Message>> SearchMessagesAsync(Guid userId, string keyword);
    }
}
