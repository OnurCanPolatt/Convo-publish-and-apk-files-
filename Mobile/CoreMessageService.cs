using Domain.Entities;
using Domain.Interfaces;
using Domain.Models.Dto;
using Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

public class CoreMessageService : IMessageService
{
    private readonly ApplicationDbContext _context;
    
    // 💡 IServiceProvider kaldırıldı. İhtiyaç duyulan servisler doğrudan eklendi:
    private readonly IFriendService _friendService;
    private readonly IGroupService _groupService;

    // Constructor, tüm gerekli bağımlılıkları alır.
    public CoreMessageService(
        ApplicationDbContext context, 
        IFriendService friendService, 
        IGroupService groupService)
    {
        _context = context;
        _friendService = friendService;
        _groupService = groupService;
    }

    // --- TEMEL MESAJ CRUD METOTLARI (DB İşlemleri) ---
    
    public async Task<bool> SaveMessage(Message message)
    {
        try
        {
            if (message == null)
            {
                return false;
            }

            await _context.Messages.AddAsync(message);
            return await _context.SaveChangesAsync() > 0;
        }
        catch (DbUpdateException ex)
        {
            Console.WriteLine($"❌ SaveMessage DB Hatası: {ex.InnerException?.Message}");
            return false;
        }
    }
    
    public async Task<List<Message>> GetMessagesAsync(Guid senderId, Guid receiverId)
    {
        var query = _context.Messages
            .Where(m => (m.SenderId == senderId && m.ReceiverId == receiverId) ||
        (m.SenderId == receiverId && m.ReceiverId == senderId));
        
        return await query
            .OrderBy(m => m.SentAt)
            .ToListAsync();
    }
    
    public async Task<List<Message>> GetAllMyMessages(Guid senderId)
    {
        return await _context.Messages
            .Include(m => m.Receiver)
            .Where(m => m.SenderId == senderId)
            .OrderBy(m => m.SentAt)
            .ToListAsync(); 
    }
    
    public async Task<List<Message>> GetGroupMessagesAsync(Guid groupId)
    {
        return await _context.Messages
            .Where(m => m.ChatRoomId == groupId && m.ChatRoomId != null)
            .OrderBy(m => m.SentAt)
            .ToListAsync();
    }

    // --- KONUŞMA LİSTESİ METODU ---
    
    public async Task<List<ConversationListItemDto>> GetRecentConversationsAsync(Guid userId)
    {
        // 💡 Artık temiz bağımlılıklar kullanılıyor.
        var conversations = new List<ConversationListItemDto>();

        // --- 1. Adım: P2P Konuşmalarını (Arkadaşları) Çek ---
        var friends = await _friendService.GetMyFriendsWithoutNotDeleted(); 

        var friendUsers = new List<AppUser>();
        foreach (var friend in friends)
        {
            var friendUser = (friend.UserId == userId) ? friend.FriendUser : friend.User;
            if (friendUser != null)
            {
                friendUsers.Add(friendUser);
            }
        }

        // --- 2. Adım: P2P Listesini Oluştur ---
        foreach (var friendUser in friendUsers)
        {
            conversations.Add(new ConversationListItemDto
            {
                Id = friendUser.Id,
                Name = friendUser.UserName ?? "Bilinmeyen Kullanıcı",
                Type = ConversationType.Personal
                // ImageUrl DB'den gelmiyorsa null olarak kalır.
            });
        }

        // --- 3. Adım: Grup Konuşmalarını Çek ---
        var groups = await _groupService.GetMyGroups(userId);

        foreach (var group in groups)
        {
            conversations.Add(new ConversationListItemDto
            {
                Id = group.Id,
                Name = group.Name,
                ImageUrl = group.ImageUrl, 
                Type = ConversationType.Group
            });
        }

        // --- 4. Adım: Birleşik Listeyi Sırala ve Dön ---
        return conversations.OrderBy(c => c.Name).ToList();
    }
}