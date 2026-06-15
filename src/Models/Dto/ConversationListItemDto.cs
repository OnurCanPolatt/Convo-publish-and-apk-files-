namespace Domain.Models.Dto;

    public enum ConversationType
    {
        Personal,
        Group
    }

    public class ConversationListItemDto
    {
        public Guid Id { get; set; } // Bu, UserId veya GroupId olabilir
        public string Name { get; set; } = string.Empty; // UserName veya GroupName
        public string? ImageUrl { get; set; } // Profil fotosu veya Grup fotosu
        public ConversationType Type { get; set; }

        // Bu 3 alanı daha sonra ekleyerek listeyi daha da güçlendirebiliriz:
        // public string? LastMessage { get; set; }
        // public DateTime? LastMessageDate { get; set; }
        // public int UnreadCount { get; set; }
    }
