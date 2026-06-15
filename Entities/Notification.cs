using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Domain.Enums;

namespace Domain.Entities
{
    public class Notification
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        // Bildirimi alan kullanıcı (TO)
        public Guid UserId { get; set; }
        // ✅ YENİ: Bildirimi gönderen kullanıcı (FROM) - ÖNEMLİ!
        public Guid FromUserId { get; set; }
        public NotificationType Type { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public bool IsRead { get; set; } = false;

        // ✅ YENİ: Ne zaman okundu
        public DateTime? ReadAt { get; set; }

        // ✅ YENİ: Soft delete için
        public bool IsActive { get; set; } = true;

        // ✅ YENİ: Öncelik seviyesi
        public NotificationPriority Priority { get; set; } = NotificationPriority.Normal;

        public AppUser User { get; set; }
        public AppUser FromUser { get; set; }

    }

}