using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Domain.Enums;

namespace Domain.Entities
{
    public class ChatRoomMember
    {
        public Guid Id { get; set; }
        public Guid ChatRoomId { get; set; }
        public Guid UserId { get; set; }
        public ChatRoomRole Role { get; set; } = ChatRoomRole.Member;
        public DateTime JoinedAt { get; set; }
        public DateTime? LastReadAt { get; set; }   // Son okunan mesaj zamanı
        public bool IsMuted { get; set; } = false;  // Sessiz mod
        public bool IsActive { get; set; } = true;  // Üyelikten çıktı mı

        public bool IsHidden { get; set; } = false;
        
        // Navigation properties
        [JsonIgnore]
        public ChatRoom? ChatRoom { get; set; }
        public AppUser? User { get; set; }
    }
}
