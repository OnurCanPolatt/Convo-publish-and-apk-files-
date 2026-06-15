using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Entities
{
    public class Friend
    {
        public Guid Id { get; set; }
        public Guid UserId { get; set; }        // Kim arkadaş ekliyor
        public Guid FriendId { get; set; }  // Kimi arkadaş ekliyor
        public DateTime CreatedAt { get; set; }
        
        public bool IsHiddenByFriendUserId { get; set; } = false;
        // Navigation properties
        public AppUser User { get; set; }
        public AppUser FriendUser { get; set; }
    }
}
