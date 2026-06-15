using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Domain.Enums;
namespace Domain.Entities
{
    public class ChatRoom
    {
        public Guid Id { get; set; }
        public string? Name { get; set; }           // Grup adı (private chat'te null)
        public string? Description { get; set; }
        public ChatRoomType Type { get; set; }
        public Guid? CreatedByUserId { get; set; }  // Kim oluşturdu
        public DateTime CreatedAt { get; set; }
        public bool IsActive { get; set; } = true;
        public string? ImageUrl { get; set; }       // Grup fotoğrafı

        // Navigation properties
        public AppUser? CreatedByUser { get; set; }
        public ICollection<ChatRoomMember>? Members { get; set; } = new List<ChatRoomMember>();
        public ICollection<Message>? Messages { get; set; } = new List<Message>(); // Boş liste ile initialize et
    }
}
