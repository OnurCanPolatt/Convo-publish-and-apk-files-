using System;
using System.Threading.Tasks;
using Domain.FileDataType;
using Domain.Entities;


namespace Infrastructure.Services.Events
{
    public class EventShop
    {
        // Event'ler
        public event EventHandler? OnFriendInfoSelfReceived;
        public event EventHandler? OnlineUsersUpdated;
        public event EventHandler? OnReceiveRequests;
        public event EventHandler? OnUIRefreshNeeded;
        public event EventHandler? OnP2pConferenceEnded;
        public event EventHandler? OnGroupConferenceEnded;
        public event EventHandler? OnGroupInfoUpdated;
        public event EventHandler? OnUserInfoUpdated;
        public event EventHandler<int>? OnRequestCountChanged;
        public event EventHandler<Guid>? OnUnreadCountChanged;
        public event EventHandler<Guid>? OnUnreadGroupCountChanged;



        public event EventHandler<(string userId, string friendInfo)>? OnFriendInfoReceived;
        public event EventHandler<(Guid senderId,string message, string fileUrl, string messageType,long filesize ,Guid? groupId,string? messageId, Guid? receiverId,DateTime sentAt)>? OnReceiveMessage;
        public event EventHandler<(Guid senderId, string newMessage, string fileUrl, string messageType, Guid? groupId)>? OnReceiveFileMessage;

        public event EventHandler<(int userId, Guid conferenceId)>? OnFriendJoinedConference;


        // TRIGGER METHODLARİ - Dışarıdan çağrılacak
        public void TriggerFriendInfoSelfReceived()
        {
            OnFriendInfoSelfReceived?.Invoke(this, EventArgs.Empty);
        }
        public void TriggerUserInfoUpdated()
        {
            OnUserInfoUpdated?.Invoke(this, EventArgs.Empty);
        }


        public void TriggerOnlineUsersUpdated()
        {
            OnlineUsersUpdated?.Invoke(this, EventArgs.Empty);
        }

        public void TriggerReceiveRequests()
        {
            OnReceiveRequests?.Invoke(this, EventArgs.Empty);
        }

        public void TriggerUIRefreshNeeded()
        {
            OnUIRefreshNeeded?.Invoke(this, EventArgs.Empty);
        }
        public void TriggerP2pConferenceEnded()
        {
            OnP2pConferenceEnded?.Invoke(this, EventArgs.Empty);
        }
        public void TriggerGroupConferenceEnded()
        {
            OnGroupConferenceEnded?.Invoke(this, EventArgs.Empty);
        }
        public void TriggerOnGroupInfoUpdated()
        {
            OnGroupInfoUpdated?.Invoke(this, EventArgs.Empty);
        }
        public void TriggerUnreadCount(Guid userId)
        {
            OnUnreadCountChanged?.Invoke(this, userId);
        }
        public void TriggerGroupUnreadCount(Guid groupId)
        {
            OnUnreadGroupCountChanged?.Invoke(this, groupId);
        }
        public void TriggerFriendInfoReceived(string userId, string friendInfo)
        {
            OnFriendInfoReceived?.Invoke(this, (userId, friendInfo));
        }
        public void TriggerRequestCountChanged(int count)
        {
            OnRequestCountChanged?.Invoke(this, count);
        }

        public void TriggerReceiveMessage(Guid senderId,
            string message, string? fileUrl, string messageType, long filesize, Guid? groupId = null, string? messageId = null, Guid? receiverId = null, DateTime? sentAt = null)
        {
            // Eğer sentAt null gelirse (fallback) şu anı kullan
            var finalDate = sentAt ?? DateTime.Now;
            
            OnReceiveMessage?.Invoke(this, (senderId, message, fileUrl, messageType, filesize, groupId, messageId, receiverId, finalDate));
        }

        public void TriggerReceiveFileMessage(Guid senderId,string newMessage,string fileUrl,string messageType,
             Guid? groupId = null)
        {
            OnReceiveFileMessage?.Invoke(this, (senderId, newMessage, fileUrl, messageType, groupId));
        }
        
  
        public void TriggerFriendJoinedConference(int userId, Guid conferenceId)
        {
            OnFriendJoinedConference?.Invoke(this, (userId, conferenceId));
        }
    }
}