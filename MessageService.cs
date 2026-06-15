using Domain.Entities;
using Domain.Interfaces;
using Domain.Models.Dto;    
using Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;

namespace Infrastructure.Services
{
    public class MessageService : IMessageService
    {
        private readonly ApplicationDbContext _context;
        private readonly IServiceProvider _serviceProvider; // ✅ YENİ
        public MessageService(ApplicationDbContext context,IServiceProvider serviceProvider)
        {
            _context = context;
            _serviceProvider= serviceProvider;
        }
        public async Task<bool> SaveMessage(Message message)
        {
            // ⚠️ RACE CONDITION FIX: Tüm operasyonu transaction içinde yap
            using var transaction = await _context.Database.BeginTransactionAsync();
            try
            {
                if (message == null)
                {
                    await transaction.RollbackAsync();
                    return false;
                }

                // ✅ 1. ADIM: ID Çakışmasını Engelle (Transaction içinde lock)
                var existingMessage = await _context.Messages.AnyAsync(m => m.Id == message.Id);
                if (existingMessage)
                {
                    Console.WriteLine($"⚠️ Mesaj zaten veritabanında var (ID: {message.Id}), unhide ve cache güncelleme yapılıyor.");
                    await PerformUnhide(message);

                    // ✅ KRİTİK FIX: Mesaj zaten varsa bile cache'i güncelle!
                    var cacheService = _serviceProvider.GetRequiredService<ICacheService>();
                    if (message.ChatRoomId != null && message.ChatRoomId != Guid.Empty)
                    {
                        await cacheService.AddGroupMessageToCacheAsync(message, message.ChatRoomId.Value);
                        Console.WriteLine($"✅ Var olan grup mesajı cache'e eklendi: {message.Id}");
                    }
                    else if (message.ReceiverId != null)
                    {
                        await cacheService.AddMessageToCacheAsync(message, message.SenderId, message.ReceiverId.Value);
                        await cacheService.AddMessageToCacheAsync(message, message.ReceiverId.Value, message.SenderId);
                        Console.WriteLine($"✅ Var olan P2P mesajı cache'e eklendi: {message.Id}");
                    }

                    await transaction.CommitAsync();
                    return true;
                }

                // Mevcut SQLite düzeltmen
                if (message.ChatRoomId != null && message.ChatRoomId != Guid.Empty)
                {
                    message.ReceiverId = null;
                }

                await _context.Messages.AddAsync(message);
                var isSaved = await _context.SaveChangesAsync() > 0;
                await transaction.CommitAsync();

                if (isSaved)
                {
                    await PerformUnhide(message);

                    // ✅ FIX: Mesaj başarıyla kaydedildikten sonra cache'i güncelle
                    var cacheService = _serviceProvider.GetRequiredService<ICacheService>();

                    if (message.ChatRoomId != null && message.ChatRoomId != Guid.Empty)
                    {
                        // Grup mesajı - grup cache'ine ekle
                        await cacheService.AddGroupMessageToCacheAsync(message, message.ChatRoomId.Value);
                        Console.WriteLine($"✅ [SaveMessage] Grup mesajı cache'e eklendi: {message.Id}");
                    }
                    else if (message.ReceiverId != null)
                    {
                        // P2P mesajı - her iki kullanıcının cache'ine de ekle
                        await cacheService.AddMessageToCacheAsync(message, message.SenderId, message.ReceiverId.Value);
                        await cacheService.AddMessageToCacheAsync(message, message.ReceiverId.Value, message.SenderId);
                        Console.WriteLine($"✅ [SaveMessage] P2P mesajı cache'e eklendi: {message.Id}");
                    }
                }

                return isSaved;
            }
            catch (DbUpdateException ex)
            {
                await transaction.RollbackAsync();
                // ⚠️ UNIQUE constraint hatası beklenen bir durum (race condition)
                if (ex.InnerException?.Message?.Contains("UNIQUE constraint") == true)
                {
                    Console.WriteLine($"⚠️ UNIQUE constraint race condition (beklenen): {message.Id}");
                    // Mesaj zaten kayıtlı, unhide yapalım
                    try
                    {
                        await PerformUnhide(message);
                        return true; // Mesaj var, sorun yok
                    }
                    catch
                    {
                        return true; // Unhide başarısız olsa da mesaj DB'de
                    }
                }

                Console.WriteLine($"❌ Veritabanı Kayıt Hatası: {ex.InnerException?.Message ?? ex.Message}");
                return false;
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                Console.WriteLine($"❌ Mesaj kaydetme hatası: {ex.Message}");
                return false;
            }
        }
        private async Task PerformUnhide(Message message)
        {
            var friendService = _serviceProvider.GetRequiredService<IFriendService>();
            var groupService = _serviceProvider.GetRequiredService<IGroupService>();

            if (message.ChatRoomId != null && message.ChatRoomId != Guid.Empty)
            {
                // ✅ GRUP MESAJI: Tüm üyelerin (gönderen hariç) IsHidden'ını false yap
                var memberIds = await groupService.GetGroupMemberIdsAsync(message.ChatRoomId.Value);
                foreach (var memberId in memberIds)
                {
                    // Göndereninki zaten unhidden, diğerlerini unhide et
                    if (memberId != message.SenderId)
                    {
                        await groupService.UnhideGroupChatAsync(message.ChatRoomId.Value, memberId);
                    }
                }
            }
            else if (message.ReceiverId != null)
            {
                // ✅ P2P MESAJI: Alıcının IsHidden'ını false yap
                await friendService.UnhidePrivateChatAsync(message.ReceiverId.Value, message.SenderId);
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
        // ✅ YENİ BİRLEŞİK METODUN GÖVDESİ
        public async Task<List<ConversationListItemDto>> GetRecentConversationsAsync(Guid userId)
        {
            // ✅ Servisleri doğrudan _serviceProvider'dan alıyoruz.
            var friendService = _serviceProvider.GetRequiredService<IFriendService>();
            var groupService = _serviceProvider.GetRequiredService<IGroupService>();
    
            // ❌ SİLİNDİ: var imageService = _serviceProvider.GetRequiredService<IImageService>();

            var conversations = new List<ConversationListItemDto>();

            // --- 1. Adım: P2P Konuşmalarını (Arkadaşları) Çek ---
            var friends = await friendService.GetMyFriendsWithoutNotDeleted();

            var friendUsers = new List<AppUser>();
            foreach (var friend in friends)
            {
                // ✅ FIX: GetMyFriendsWithoutNotDeleted artık sadece UserId=userId döndürüyor
                // Bu yüzden her zaman FriendUser almalıyız
                var friendUser = friend.FriendUser;
                if (friendUser != null)
                {
                    friendUsers.Add(friendUser);
                }
            }

            // ❌ SİLİNDİ: 2. Adım (TÜM Fotoğrafları Çekme) kaldırıldı.

            // --- 3. Adım: P2P Listesini (Fotoğraf OLMADAN) Oluştur ---
            foreach (var friendUser in friendUsers)
            {
                // ✅ FIX: Kendimizi listeden filtrele (asla kendi kullanıcı profilimizi gösterme)
                if (friendUser.Id == userId)
                {
                    Console.WriteLine($"⚠️ Kendi kullanıcı ID'miz conversation listesine eklenmeye çalışıldı, filtrelendi: {friendUser.Id}");
                    continue;
                }

                conversations.Add(new ConversationListItemDto
                {
                    Id = friendUser.Id,
                    Name = friendUser.UserName ?? "Bilinmeyen Kullanıcı",
                    // ❌ SİLİNDİ: ImageUrl satırı kaldırıldı.
                    // DTO'daki ImageUrl alanı 'null' olarak kalacak.
                    Type = ConversationType.Personal
                });
            }

            // --- 4. Adım: Grup Konuşmalarını Çek ---
            var groups = await groupService.GetMyGroups(userId);

            foreach (var group in groups)
            {
                conversations.Add(new ConversationListItemDto
                {
                    Id = group.Id,
                    Name = group.Name,
                    ImageUrl = group.ImageUrl, // Grup fotoğrafı DB'den geliyor, bu kalsın.
                    Type = ConversationType.Group
                });
            }

            // --- 5. Adım: Birleşik Listeyi Sırala ve Dön ---
            return conversations.OrderBy(c => c.Name).ToList();
        }
}
    }

