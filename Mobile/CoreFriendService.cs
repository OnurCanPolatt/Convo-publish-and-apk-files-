using Domain.Constants;
using Domain.Entities;
using Domain.Enums;
using Domain.Interfaces;
using Domain.Interfaces.MobileInterface;
using Infrastructure.Data;
using Infrastructure.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using System.Linq;

namespace Infrastructure.Services.Mobile
{
    public class CoreFriendService : ICoreFriendService
    {
        private readonly ApplicationDbContext _context;
        private readonly IUserService _userService;
        private readonly ICoreNotificationService _notificationService;
        private readonly IHubContext<NotificationHub> _hubContext;
        private readonly ICacheService _cacheService;
        private readonly IFcmService _fcmService; // ✅ Push notification için

        public CoreFriendService(
            ApplicationDbContext context,
            IUserService userService,
            ICoreNotificationService notificationService,
            IHubContext<NotificationHub> hubContext,
            ICacheService cacheService,
            IFcmService fcmService) // ✅ DI ile inject ediyoruz
        {
            _context = context;
            _userService = userService;
            _notificationService = notificationService;
            _hubContext = hubContext;
            _cacheService = cacheService;
            _fcmService = fcmService;
        }
        // CoreFriendService.cs içine ekle
        public async Task<int> CalculateStatus(Guid userId, Guid targetId)
        {
            // 1. Arkadaşlık tablosuna bak (Durum 3)
            var areFriends = await _context.Friends.AnyAsync(f => 
                f.UserId == userId && f.FriendId == targetId);
    
            if (areFriends) return 3; // AreFriends

            // 2. İstekler tablosuna bak
            var request = await _context.Requests.FirstOrDefaultAsync(r => 
                (r.SenderId == userId && r.ReceiverId == targetId) ||
                (r.SenderId == targetId && r.ReceiverId == userId));

            if (request != null)
            {
                // İsteği biz mi attık? (Durum 1)
                if (request.SenderId == userId) return 1; // SentByMe
        
                // İstek bize mi geldi? (Durum 2)
                return 2; // SentToMe
            }

            // 3. Hiçbir ilişki yok (Durum 0)
            return 0; // None
        }
        // CoreFriendService.cs içindeki TriggerGlobalUpdate metodunu şu şekilde güncelle:

        private async Task TriggerGlobalUpdate(Guid targetUserId, Guid senderId, NotificationType? type = null, string message = "")
        {
            try 
            {
                var targetIdStr = targetUserId.ToString();
                var senderIdStr = senderId.ToString();

                // 1. Cache temizleme
                var result = await _cacheService.InvalidateRequestsCacheAsync(targetUserId);

                // 2. Bildirimleri gönder
                await _hubContext.Clients.User(targetIdStr).SendAsync("FriendInfo", senderIdStr, message);
                await _hubContext.Clients.User(targetIdStr).SendAsync("RequestsLoaded", result.requests, result.count);
        
                // 🚀 3. YENİ: Parametreli Durum Güncellemesi
                int statusForTarget = await CalculateStatus(targetUserId, senderId);
                int statusForSender = await CalculateStatus(senderId, targetUserId);

                // Hedef kullanıcıya (alıcıya) yeni durumu gönder
                await _hubContext.Clients.User(targetIdStr).SendAsync("FriendListChanged", senderIdStr, statusForTarget);

                // Eğer bu bir 'Onay', 'Silme' veya 'Red' ise (type null değilse) gönderen kişiye de sinyal gönder
                if (type != null) 
                {
                    await _hubContext.Clients.User(senderIdStr).SendAsync("FriendListChanged", targetIdStr, statusForSender);
                }
            }
            catch (Exception ex) { Console.WriteLine($"❌ Trigger Hatası: {ex.Message}"); }
        }
        public async Task<bool> SendFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null) return false;
            var myUserId = currentUser.Id;

            try {
                var existingRequest = await _context.Requests.FirstOrDefaultAsync(fr =>
                    ((fr.SenderId == myUserId && fr.ReceiverId == friendId) ||
                     (fr.SenderId == friendId && fr.ReceiverId == myUserId)));

                if (existingRequest != null) {
                    existingRequest.RequestType = RequestType.FriendRequest;
                    existingRequest.SentAt = DateTime.UtcNow;
                    _context.Requests.Update(existingRequest);
                } else {
                    _context.Requests.Add(new Request {
                        Id = Guid.NewGuid(),
                        SenderId = myUserId,
                        ReceiverId = friendId,
                        SentAt = DateTime.UtcNow,
                        RequestType = RequestType.FriendRequest
                    });
                }
                await _context.SaveChangesAsync();

                // ✅ Push notification gönder
                await _fcmService.SendNotificationAsync(
                    friendId,
                    "Yeni Arkadaşlık İsteği",
                    $"{currentUser.UserName} size arkadaşlık isteği gönderdi.",
                    myUserId,
                    isGroup: false,
                    currentUser.UserName,
                    "FRIEND_NOTIFICATION"
                );

                // ✅ Request ikonunu tetikle
                await TriggerGlobalUpdate(friendId, myUserId, null, NotificationConstants.Titles.FriendRequest);
                return true;
            } catch (Exception ex) {
                Console.WriteLine($"❌ SendFriendRequest hatası: {ex.Message}");
                return false;
            }
        }

        public async Task<bool> AcceptFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null) return false;
            var myUserId = currentUser.Id;

            try {
                var friendRequest = await _context.Requests.FirstOrDefaultAsync(f => f.SenderId == friendId && f.ReceiverId == myUserId);
                if (friendRequest == null) return false;

                // ✅ FIX: Önce mevcut kayıtları kontrol et, varsa temizle
                var existingFriendships = await _context.Friends
                    .Where(f => (f.UserId == myUserId && f.FriendId == friendId) ||
                                (f.UserId == friendId && f.FriendId == myUserId))
                    .ToListAsync();

                if (existingFriendships.Any())
                {
                    _context.Friends.RemoveRange(existingFriendships);
                }

                // ✅ FIX: Her iki yönü de ekle (A→B ve B→A)
                _context.Friends.Add(new Friend {
                    Id = Guid.NewGuid(),
                    UserId = myUserId,
                    FriendId = friendId,
                    CreatedAt = DateTime.UtcNow
                });
                _context.Friends.Add(new Friend {
                    Id = Guid.NewGuid(),
                    UserId = friendId,
                    FriendId = myUserId,
                    CreatedAt = DateTime.UtcNow
                });

                _context.Requests.Remove(friendRequest);
                await _context.SaveChangesAsync();

                await _cacheService.RemoveRequestFromCacheAsync(myUserId, friendId);
                await _cacheService.RemoveRequestFromCacheAsync(friendId, myUserId);

                // Bildirimi kaydet
                await _notificationService.SaveNotificationAsync(friendId, myUserId, NotificationType.FriendRequestAccepted, NotificationPriority.Normal);

                // ✅ Push notification gönder (mobil uygulama arka plandaysa)
                var friendUser = await _context.Users.FirstOrDefaultAsync(u => u.Id == friendId);
                if (friendUser != null)
                {
                    await _fcmService.SendNotificationAsync(
                        friendId,
                        "Arkadaşlık İsteği Kabul Edildi",
                        $"{currentUser.UserName} arkadaşlık isteğinizi kabul etti.",
                        myUserId,
                        isGroup: false,
                        currentUser.UserName,
                        "FRIEND_NOTIFICATION"
                    );
                }

                // ✅ Bildirim ikonunu tetikle
                await TriggerGlobalUpdate(friendId, myUserId, NotificationType.FriendRequestAccepted, NotificationConstants.Titles.FriendRequestAccepted);
                return true;
            } catch (Exception ex) {
                Console.WriteLine($"❌ AcceptFriendRequest hatası: {ex.Message}");
                return false;
            }
        }

        public async Task<bool> RejectFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null) return false;
            var myUserId = currentUser.Id;

            try {
                var existingRequest = await _context.Requests.FirstOrDefaultAsync(fr =>
                    (fr.SenderId == myUserId && fr.ReceiverId == friendId) ||
                    (fr.SenderId == friendId && fr.ReceiverId == myUserId));

                if (existingRequest == null) return false;
                _context.Requests.Remove(existingRequest);
                await _context.SaveChangesAsync();

                await _cacheService.RemoveRequestFromCacheAsync(myUserId, friendId);
                await _cacheService.RemoveRequestFromCacheAsync(friendId, myUserId);

                await _notificationService.SaveNotificationAsync(friendId, myUserId, NotificationType.FriendRequestReject, NotificationPriority.Normal);

                // ✅ Push notification gönder
                await _fcmService.SendNotificationAsync(
                    friendId,
                    "Arkadaşlık İsteği Reddedildi",
                    $"{currentUser.UserName} arkadaşlık isteğinizi reddetti.",
                    myUserId,
                    isGroup: false,
                    currentUser.UserName,
                    "FRIEND_NOTIFICATION"
                );

                // ✅ Bildirim ikonunu tetikle
                await TriggerGlobalUpdate(friendId, myUserId, NotificationType.FriendRequestReject, NotificationConstants.Titles.FriendRequestRejected);
                return true;
            } catch (Exception ex) {
                Console.WriteLine($"❌ RejectFriendRequest hatası: {ex.Message}");
                return false;
            }
        }

        public async Task<bool> RemoveFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null) return false;
            var myUserId = currentUser.Id;

            try {
                var existingRequest = await _context.Requests.FirstOrDefaultAsync(fr =>
                    (fr.SenderId == myUserId && fr.ReceiverId == friendId) ||
                    (fr.SenderId == friendId && fr.ReceiverId == myUserId));

                if (existingRequest == null) return false;
                _context.Requests.Remove(existingRequest);
                await _context.SaveChangesAsync();

                await _cacheService.RemoveRequestFromCacheAsync(myUserId, friendId);
                await _cacheService.RemoveRequestFromCacheAsync(friendId, myUserId);

                await _notificationService.SaveNotificationAsync(friendId, myUserId, NotificationType.FriendRequestRemoved, NotificationPriority.Normal);

                // ✅ Push notification gönder
                await _fcmService.SendNotificationAsync(
                    friendId,
                    "Arkadaşlık İsteği Geri Çekildi",
                    $"{currentUser.UserName} arkadaşlık isteğini geri çekti.",
                    myUserId,
                    isGroup: false,
                    currentUser.UserName,
                    "FRIEND_NOTIFICATION"
                );

                await TriggerGlobalUpdate(friendId, myUserId, NotificationType.FriendRequestRemoved, NotificationConstants.Titles.FriendRequestRemoved);
                return true;
            } catch (Exception ex) {
                Console.WriteLine($"❌ RemoveFriendRequest hatası: {ex.Message}");
                return false;
            }
        }

        public async Task<bool> RemoveFriend(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null) return false;
            var myUserId = currentUser.Id;

            try {
                var friendships = await _context.Friends.Where(f =>
                    (f.UserId == myUserId && f.FriendId == friendId) ||
                    (f.UserId == friendId && f.FriendId == myUserId)).ToListAsync();

                if (!friendships.Any()) return false;

                _context.Friends.RemoveRange(friendships);
                await _context.SaveChangesAsync();

                await _notificationService.SaveNotificationAsync(friendId, myUserId, NotificationType.FriendRemoved, NotificationPriority.Normal);

                // ✅ Push notification gönder
                await _fcmService.SendNotificationAsync(
                    friendId,
                    "Arkadaşlıktan Çıkarıldınız",
                    $"{currentUser.UserName} sizi arkadaşlıktan çıkardı.",
                    myUserId,
                    isGroup: false,
                    currentUser.UserName,
                    "FRIEND_NOTIFICATION"
                );

                // ✅ Bildirim ikonunu tetikle
                await TriggerGlobalUpdate(friendId, myUserId, NotificationType.FriendRemoved, NotificationConstants.Titles.FriendRemoved);
                return true;
            } catch (Exception ex) {
                Console.WriteLine($"❌ RemoveFriend hatası: {ex.Message}");
                return false;
            }
        }

        public async Task<List<object>> GetFriendRequestsForMobile(Guid currentUserId)
        {
            return await _context.Requests.Include(r => r.Sender).Where(fr => fr.ReceiverId == currentUserId || fr.SenderId == currentUserId).OrderByDescending(fr => fr.SentAt)
                .Select(fr => new {
                    id = fr.Id,
                    senderId = fr.SenderId,
                    receiverId = fr.ReceiverId,
                    sentAt = fr.SentAt,
                    sender = new { userName = fr.Sender.UserName },
                    senderName = fr.Sender.UserName, 
                    message = fr.SenderId == currentUserId ? "Arkadaşlık isteği gönderdiniz." : "Size bir arkadaşlık isteği gönderdi.",
                    date = fr.SentAt.ToUniversalTime().ToString("O")
                }).Cast<object>().ToListAsync();
        }

        // ... GetMyFriends ve diğer metodlar aynı kalıyor ...
        public async Task<List<Friend>> GetMyFriends() {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null) return new List<Friend>();
            var myUserId = currentUser.Id;

            // ✅ FIX: Sadece UserId=myUserId olanları döndür (duplicate önlemek için)
            // İki yönlü kayıt olduğu için bir yön yeterli
            // ✅ FIX: IsHidden (soft delete) kontrolü eklendi
            return await _context.Friends
                .Include(f => f.User)
                .Include(f => f.FriendUser)
                .Where(f => f.UserId == myUserId && f.IsHiddenByFriendUserId == false)
                .OrderBy(f => f.FriendUser.UserName)
                .ToListAsync();
        }

        public async Task<List<Friend>> GetMyFriendsWithoutNotDeleted() {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null) return new List<Friend>();
            var myUserId = currentUser.Id;

            // ✅ FIX: Sadece UserId=myUserId olanları döndür (duplicate önlemek için)
            // İki yönlü kayıt olduğu için bir yön yeterli
            return await _context.Friends
                .Include(f => f.User)
                .Include(f => f.FriendUser)
                .Where(f => f.UserId == myUserId && f.IsHiddenByFriendUserId == false)
                .OrderBy(f => f.FriendUser.UserName)
                .ToListAsync();
        }

        public async Task HidePrivateChatAsync(Guid friendId, Guid currentUserId) {
            var friendship = await _context.Friends.FirstOrDefaultAsync(f => (f.UserId == currentUserId && f.FriendId == friendId) || (f.UserId == friendId && f.FriendId == currentUserId));
            if (friendship == null) return;
            if (friendship.UserId == currentUserId) friendship.IsHiddenByFriendUserId = true;
            else if (friendship.FriendId == currentUserId) friendship.IsHiddenByFriendUserId = true;
            await _context.SaveChangesAsync();
        }

        // ✅ Gerçekten unhide oldu mu döndürür
        public async Task<bool> UnhidePrivateChatAsync(Guid friendId, Guid currentUserId) {
            var friendship = await _context.Friends.FirstOrDefaultAsync(f => (f.UserId == currentUserId && f.FriendId == friendId) || (f.UserId == friendId && f.FriendId == currentUserId));
            if (friendship == null) return false;

            bool wasUnhidden = false;
            if (friendship.UserId == currentUserId && friendship.IsHiddenByFriendUserId)
            {
                friendship.IsHiddenByFriendUserId = false;
                wasUnhidden = true; // ✅ Gerçekten unhide olduk
            }
            else if (friendship.FriendId == currentUserId && friendship.IsHiddenByFriendUserId)
            {
                friendship.IsHiddenByFriendUserId = false;
                wasUnhidden = true; // ✅ Gerçekten unhide olduk
            }

            if (wasUnhidden)
            {
                await _context.SaveChangesAsync();
            }

            return wasUnhidden;
        }
    }
}