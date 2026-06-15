using Domain.Entities;
using Domain.Enums;
using Domain.Interfaces; // IGroupService
using Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection; // Sadece IUserService için

public class CoreGroupService : IGroupService
{
    private readonly ApplicationDbContext _context;
    private readonly IUserService _userService;
    // 💡 IJSRuntime ve IServiceProvider KALDIRILDI

    // Constructor sadece gerekli bağımlılıkları alır
    public CoreGroupService(ApplicationDbContext context, IUserService userService)
    {
        _context = context;
        _userService = userService;
    }

    // --- GRUP YÖNETİM İŞLEMLERİ (DB Mantığı) ---

    public async Task<bool> CreateGroup(ChatRoom chatRoom)
    {
        try
        {
            _context.ChatRooms.Add(chatRoom);
            await _context.SaveChangesAsync();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Grup oluşturma hatası: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> AddMembersToGroup(Guid groupId, List<Guid> memberIds)
    {
        try
        {
            var members = memberIds.Select(memberId => new ChatRoomMember
            {
                Id = Guid.NewGuid(),
                ChatRoomId = groupId,
                UserId = memberId,
                Role = ChatRoomRole.Member,
                JoinedAt = DateTime.UtcNow,
                IsActive = true,
                IsHidden = false 
            }).ToList();

            _context.ChatRoomMembers.AddRange(members);
            await _context.SaveChangesAsync();
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Üye ekleme hatası: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> DeleteMemberFromGroup(Guid groupId, Guid memberId)
    {
        try
        {
            var member = await _context.ChatRoomMembers
                .FirstOrDefaultAsync(m => m.ChatRoomId == groupId && m.UserId == memberId);

            if (member != null)
            {
                _context.ChatRoomMembers.Remove(member);
                await _context.SaveChangesAsync();
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Üye silme hatası: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> AddRoleToMember(Guid groupId, Guid memberId, ChatRoomRole role)
    {
        try
        {
            var member = await _context.ChatRoomMembers
                .FirstOrDefaultAsync(m => m.ChatRoomId == groupId && m.UserId == memberId);

            if (member != null)
            {
                member.Role = role;
                await _context.SaveChangesAsync();
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Rol atama hatası: {ex.Message}");
            return false;
        }
    }

    public async Task HideGroupChatAsync(Guid groupId, Guid userId)
    {
        try
        {
            var membership = await _context.ChatRoomMembers
                .FirstOrDefaultAsync(m => m.ChatRoomId == groupId && m.UserId == userId);

            if (membership != null)
            {
                membership.IsHidden = true;
                await _context.SaveChangesAsync();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Grup gizleme hatası: {ex.Message}");
        }
    }

    // ✅ Gerçekten unhide oldu mu döndürür
    public async Task<bool> UnhideGroupChatAsync(Guid groupId, Guid userId)
    {
        try
        {
            var membership = await _context.ChatRoomMembers
                .FirstOrDefaultAsync(m => m.ChatRoomId == groupId && m.UserId == userId);

            if (membership != null && membership.IsHidden)
            {
                membership.IsHidden = false;
                await _context.SaveChangesAsync();
                return true; // ✅ Gerçekten unhide olduk
            }

            return false; // Zaten görünürdü
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Grup görünür yapma hatası: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> UpdateGroupInfo(Guid groupId, string name, string? description, string? imageUrl)
    {
        try
        {
            var group = await _context.ChatRooms.FirstOrDefaultAsync(g => g.Id == groupId);
            if (group != null)
            {
                group.Name = name;
                group.Description = description;
                group.ImageUrl = imageUrl;
                await _context.SaveChangesAsync();
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Grup bilgisi güncelleme hatası: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> UpdateMemberAdminStatus(Guid groupId, Guid memberId, bool isAdmin)
    {
        try
        {
            var member = await _context.ChatRoomMembers
                .FirstOrDefaultAsync(m => m.ChatRoomId == groupId && m.UserId == memberId);

            if (member != null)
            {
                member.Role = isAdmin ? ChatRoomRole.Admin : ChatRoomRole.Member;
                await _context.SaveChangesAsync();
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Admin statüsü güncelleme hatası: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> LeaveGroup(Guid groupId, Guid userId)
    {
        try
        {
            var member = await _context.ChatRoomMembers
                .FirstOrDefaultAsync(m => m.ChatRoomId == groupId && m.UserId == userId);

            if (member != null)
            {
                _context.ChatRoomMembers.Remove(member);
                await _context.SaveChangesAsync();
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Gruptan ayrılma hatası: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> DeleteGroup(Guid groupId, Guid requestedByUserId)
    {
        try
        {
            var group = await _context.ChatRooms
                .Include(g => g.Members)
                .FirstOrDefaultAsync(g => g.Id == groupId);

            if (group != null && group.CreatedByUserId == requestedByUserId)
            {
                group.IsActive = false;
                await _context.SaveChangesAsync();
                return true;
            }
            return false;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"CoreGroupService - Grup silme hatası: {ex.Message}");
            return false;
        }
    }

    // --- GET METOTLARI (ZATEN TEMİZDİ) ---

    public async Task<List<ChatRoom>> GetMyGroups(Guid currentUserId)
    {
        return await _context.ChatRoomMembers
            .AsNoTracking()
            .Include(m => m.ChatRoom)
            .Where(m => m.UserId == currentUserId && m.IsHidden == false && m.ChatRoom.IsActive)
            .Select(m => m.ChatRoom)
            .ToListAsync();
    }

    public async Task<ChatRoom> GetGroupInfo(Guid groupId)
    {
        return await _context.ChatRooms
            .Include(room => room.Members)
                .ThenInclude(member => member.User)
            .Include(room => room.CreatedByUser)
            .FirstOrDefaultAsync(room => room.Id == groupId && room.IsActive);
    }
    public async Task<List<Guid>> GetGroupMemberIdsAsync(Guid groupId)
    {
        return await _context.ChatRoomMembers
            .Where(m => m.ChatRoomId == groupId && m.IsActive)
            .Select(m => m.UserId)
            .ToListAsync();
    }
    
    // GetFreshGroupInfo metodu artık aynı context'i kullanmalı, scoped logic kaldırıldı
    public async Task<ChatRoom> GetFreshGroupInfo(Guid groupId)
    {
        // Not: Aslında EF Core, aynı request scope'unda zaten en güncel veriyi çeker.
        // Bu metot, GetGroupInfo ile aynı işi yapacak, ancak aktif üyeler filtresi eklenebilir.
        
        return await _context.ChatRooms
            .Include(r => r.Members.Where(m => m.IsActive)) // sadece aktif üyeler
            .ThenInclude(m => m.User)
            .Include(r => r.CreatedByUser)
            .FirstOrDefaultAsync(r => r.Id == groupId && r.IsActive);
    }


    public async Task<ChatRoom> GetGroupInfoWithActiveMembers(Guid groupId)
    {
        return await _context.ChatRooms
            .Include(room => room.Members.Where(m => m.IsActive))  // Sadece aktif üyeler
                .ThenInclude(member => member.User)
            .Include(room => room.CreatedByUser)
            .FirstOrDefaultAsync(room => room.Id == groupId && room.IsActive);
    }
}