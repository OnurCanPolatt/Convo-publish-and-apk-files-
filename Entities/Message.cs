using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Domain.Enums;
using Domain.FileDataType;

namespace Domain.Entities
{
    public class Message
    {
        public Guid Id { get; set; }
        public string Content { get; set; } = string.Empty;
        public MessageType Type { get; set; } = MessageType.Text;
        public Guid SenderId { get; set; }
        public Guid? ReceiverId { get; set; }
        public Guid? ChatRoomId { get; set; }
        public DateTime SentAt { get; set; }
        public bool IsRead { get; set; } = false;
        public bool IsDeleted { get; set; } = false;
        public FileData? FileData { get; set; }
        public string? FileUrl { get; set; } 
        public long? FileSize { get; set; }
        // Navigation properties
        public AppUser? Sender { get; set; }
        public AppUser? Receiver { get; set; }
        public ChatRoom? ChatRoom { get; set; }
        public Message? ReplyToMessage { get; set; }
    }
}
