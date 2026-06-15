using Domain.Constants;
using Domain.Entities;
using Domain.Enums;
using Infrastructure.Services.Events;
using Domain.Interfaces;
using Infrastructure.Data;
using Microsoft.AspNetCore.Components;
using Microsoft.EntityFrameworkCore;
using Microsoft.JSInterop;
using static System.Net.Mime.MediaTypeNames;

namespace Infrastructure.Services
{
    public class FriendService : IFriendService
    {
        private readonly ApplicationDbContext _context;
        private readonly IUserService _userService;
        private readonly IJSRuntime _jsRuntime;
        private readonly ICacheService _cacheService;
        private readonly EventShop _eventShop;
        private readonly IFcmService _fcmService; // ✅ Push notification için

        public FriendService(ApplicationDbContext context, IUserService userService, IJSRuntime jsRuntime,ICacheService cacheService,EventShop eventShop, IFcmService fcmService)
        {
            _context = context;
            _userService = userService;
            _jsRuntime = jsRuntime;
            _cacheService = cacheService;
            _eventShop = eventShop;
            _fcmService = fcmService;
        }
        //Send friend request
        public async Task<bool> SendFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            var myUserId = currentUser.Id;

            try
            {
                // ✅ Mevcut istek kontrolü (daha detaylı)
                var existingRequest = await _context.Requests
                    .FirstOrDefaultAsync(fr =>
                        ((fr.SenderId == myUserId && fr.ReceiverId == friendId) ||
                         (fr.SenderId == friendId && fr.ReceiverId == myUserId)));
                var request = new Request()
                {
                    Id = Guid.NewGuid(),
                    SenderId = myUserId,
                    ReceiverId = friendId,
                    SentAt = DateTime.UtcNow,
                    RequestType = RequestType.FriendRequest,
                };
                if (existingRequest != null)
                {
                    // Var olan isteği güncelle
                    existingRequest.RequestType = RequestType.FriendRequest;
                    existingRequest.SentAt = DateTime.UtcNow;
                    _context.Requests.Update(existingRequest);
                }
                else
                {
                    // Yeni istek ekle
                    _context.Requests.Add(request);
                }
                await _context.SaveChangesAsync();
                Console.WriteLine("✅ Friend request gönderildi");

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

                var message = NotificationConstants.Titles.FriendRequest;
                await _jsRuntime.InvokeVoidAsync("window.signalRManager.processFriendNotification",
                    friendId.ToString(), message,null);

                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ SendFriendRequest hatası: {ex.Message}");
                return false;
            }
        }
        public async Task<bool> RemoveFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            var myUserId = currentUser.Id;

            try
            {
                var existingRequest = await _context.Requests
                    .FirstOrDefaultAsync(fr => (fr.SenderId == myUserId && fr.ReceiverId == friendId) ||
                                               (fr.SenderId == friendId && fr.ReceiverId == myUserId));

                if (existingRequest == null)
                {   
                    return false;
                }
        
                _context.Requests.Remove(existingRequest);
                await _context.SaveChangesAsync();
        
                // ✅ CACHE'İ GÜNCELLE - HER İKİ KULLANICI İÇİN
                await _cacheService.RemoveRequestFromCacheAsync(myUserId, friendId);
                await _cacheService.RemoveRequestFromCacheAsync(friendId, myUserId);
        
                var myRequestCount = (await _cacheService.GetUserRequests(myUserId)).Count;
                _eventShop.TriggerRequestCountChanged(myRequestCount);

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

                var message = NotificationConstants.Titles.FriendRequestRemoved;
                await _jsRuntime.InvokeVoidAsync("window.signalRManager.processFriendNotification",
                    friendId.ToString(), message, (int)NotificationType.FriendRequestRemoved);

                return true;
            }
            catch
            {
                return false;
            }
        }
        public async Task<bool> AcceptFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            if (currentUser == null)
            {
                Console.WriteLine("❌ Current user null");
                return false;
            }
            var myUserId = currentUser.Id;

            try
            {
                var friendRequest = await _context.Requests
                    .FirstOrDefaultAsync(f => f.SenderId == friendId && f.ReceiverId == myUserId);

                if (friendRequest == null)
                {
                    Console.WriteLine("❌ Friend request bulunamadı");
                    return false;
                }

                // ✅ FIX: Mevcut arkadaşlıkları temizle (varsa)
                var existingFriendships = await _context.Friends
                    .Where(f => (f.UserId == friendId && f.FriendId == myUserId) ||
                                (f.UserId == myUserId && f.FriendId == friendId))
                    .ToListAsync();

                if (existingFriendships.Any())
                {
                    _context.Friends.RemoveRange(existingFriendships);
                }

                // ✅ FIX: Her iki yönü de ekle (A→B ve B→A)
                _context.Friends.Add(new Friend
                {
                    Id = Guid.NewGuid(),
                    UserId = myUserId,
                    FriendId = friendId,
                    CreatedAt = DateTime.UtcNow
                });
                _context.Friends.Add(new Friend
                {
                    Id = Guid.NewGuid(),
                    UserId = friendId,
                    FriendId = myUserId,
                    CreatedAt = DateTime.UtcNow
                });

                _context.Requests.Remove(friendRequest);
                await _context.SaveChangesAsync();
        
                // ✅ CACHE'İ GÜNCELLE - HER İKİ KULLANICI İÇİN
                await _cacheService.RemoveRequestFromCacheAsync(myUserId, friendId);
                await _cacheService.RemoveRequestFromCacheAsync(friendId, myUserId);
                
                var myRequestCount = (await _cacheService.GetUserRequests(myUserId)).Count;
                _eventShop.TriggerRequestCountChanged(myRequestCount);

                Console.WriteLine("✅ Arkadaşlık kabul edildi");

                // ✅ Push notification gönder
                await _fcmService.SendNotificationAsync(
                    friendId,
                    "Arkadaşlık İsteği Kabul Edildi",
                    $"{currentUser.UserName} arkadaşlık isteğinizi kabul etti.",
                    myUserId,
                    isGroup: false,
                    currentUser.UserName,
                    "FRIEND_NOTIFICATION"
                );

                var message = NotificationConstants.Titles.FriendRequestAccepted;
                await _jsRuntime.InvokeVoidAsync("window.signalRManager.processFriendNotification",
                    friendId.ToString(), message, (int)NotificationType.FriendRequestAccepted);

                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ AcceptFriendRequest hatası: {ex.Message}");
                return false;
            }
        }
        public async Task<bool> RejectFriendRequest(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            var myUserId = currentUser.Id;

            try
            {
                var existingRequest = await _context.Requests
                    .FirstOrDefaultAsync(fr => (fr.SenderId == myUserId && fr.ReceiverId == friendId) ||
                                               (fr.SenderId == friendId && fr.ReceiverId == myUserId));

                if (existingRequest == null)
                {
                    return false;
                }
        
                _context.Requests.Remove(existingRequest);
                await _context.SaveChangesAsync();
        
                // ✅ CACHE'İ GÜNCELLE - HER İKİ KULLANICI İÇİN
                await _cacheService.RemoveRequestFromCacheAsync(myUserId, friendId);
                await _cacheService.RemoveRequestFromCacheAsync(friendId, myUserId);
                
                var myRequestCount = (await _cacheService.GetUserRequests(myUserId)).Count;
                _eventShop.TriggerRequestCountChanged(myRequestCount);

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

                var message = NotificationConstants.Titles.FriendRequestRejected;
                await _jsRuntime.InvokeVoidAsync("window.signalRManager.processFriendNotification",
                    friendId.ToString(), message, (int)NotificationType.FriendRequestReject);

                return true;
            }
            catch
            {
                return false;
            }
        }
        public async Task<bool> RemoveFriend(Guid friendId)
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            var myUserId = currentUser.Id;

            try
            {
                // ✅ İKİ YÖNLÜ arkadaşlığı sil
                var friendships = await _context.Friends
                    .Where(f => (f.UserId == myUserId && f.FriendId == friendId) ||
                               (f.UserId == friendId && f.FriendId == myUserId))
                    .ToListAsync();

                if (!friendships.Any())
                {
                    Console.WriteLine("❌ Arkadaşlık bulunamadı");
                    return false;
                }

                // ✅ Arkadaşlıkları sil
                _context.Friends.RemoveRange(friendships);
                await _context.SaveChangesAsync();
                Console.WriteLine("✅ Arkadaş kaldırıldı");

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

                var message = NotificationConstants.Titles.FriendRemoved;
                await _jsRuntime.InvokeVoidAsync("window.signalRManager.processFriendNotification",
                    friendId.ToString(), message, (int)NotificationType.FriendRemoved);
                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ RemoveFriend hatası: {ex.Message}");
                return false;
            }
        }
 
        public async Task<List<Request>> GetFriendRequests(Guid currentUserId)
        {
            // ✅ Status filtresi KALDIR
            return await _context.Requests
                .Where(fr => fr.SenderId == currentUserId || fr.ReceiverId == currentUserId)
                .ToListAsync();
        }
        public async Task<List<Friend>> GetMyFriends()
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            var myUserId = currentUser.Id;

            // ✅ FIX: Sadece UserId=myUserId olanları döndür (duplicate önlemek için)
            // İki yönlü kayıt olduğu için bir yön yeterli
            var friends = await _context.Friends
                .Include(f => f.User)
                .Include(f => f.FriendUser)
                .Where(f => f.UserId == myUserId && f.IsHiddenByFriendUserId == false)
                .OrderBy(f => f.FriendUser.UserName)
                .ToListAsync();

            Console.WriteLine($"✅ {friends.Count} aktif (gizlenmemiş) arkadaş bulundu.");
            return friends;
        }
        public async Task<List<Friend>> GetMyFriendsWithoutNotDeleted()
        {
            var currentUser = await _userService.GetCurrentUserAsync();
            var myUserId = currentUser.Id;

            // ✅ FIX: Sadece UserId=myUserId olanları döndür (duplicate önlemek için)
            // İki yönlü kayıt olduğu için bir yön yeterli
            var friends = await _context.Friends
                .Include(f => f.User)
                .Include(f => f.FriendUser)
                .Where(f => f.UserId == myUserId && f.IsHiddenByFriendUserId == false)
                .OrderBy(f => f.FriendUser.UserName)
                .ToListAsync();

            Console.WriteLine($"✅ {friends.Count} (gizlenmemiş) arkadaş bulundu (alfabetik sıralı)");
            return friends;
        }
        public async Task HidePrivateChatAsync(Guid friendId, Guid currentUserId)
{
    // 'friendId', bize UI'dan gelen 'diğer' kullanıcının ID'sidir.
    // 'currentUserId' ise işlemi yapan 'bizim' ID'mizdir.
    
    // Önce bu iki kullanıcı arasındaki arkadaşlık kaydını bulmamız gerekiyor.
    var friendship = await _context.Friends
        .FirstOrDefaultAsync(f => 
            (f.UserId == currentUserId && f.FriendId == friendId) ||
            (f.UserId == friendId && f.FriendId == currentUserId)
        );
    
    if (friendship == null)
    {
        throw new Exception("Arkadaşlık kaydı bulunamadı.");
    }

    // Şimdi, DOĞRU bayrağı 'true' yapmalıyız
    // (İşlemi yapan 'currentUserId' hangisiyse, onun bayrağını günceller)
    if (friendship.UserId == currentUserId)
    {
        friendship.IsHiddenByFriendUserId = true;
    }
    else if (friendship.FriendId == currentUserId)
    {
        friendship.IsHiddenByFriendUserId = true;
    }

    await _context.SaveChangesAsync();
}

// ✅ YENİ GİZLİLİĞİ KALDIRMA METODU - Gerçekten unhide oldu mu döndürür
public async Task<bool> UnhidePrivateChatAsync(Guid friendId, Guid currentUserId)
{
    // 'friendId', bize (yeni mesaj yoluyla) gelen 'diğer' kullanıcının ID'sidir.
    // 'currentUserId' ise 'bizim' ID'mizdir.

    var friendship = await _context.Friends
        .FirstOrDefaultAsync(f =>
            (f.UserId == currentUserId && f.FriendId == friendId) ||
            (f.UserId == friendId && f.FriendId == currentUserId)
        );

    if (friendship == null)
    {
        // Arkadaşlık kaydı yoksa (veya mesaj bir şekilde yanlış geldiyse)
        // hiçbir şey yapma.
        return false;
    }

    // Sadece gizliyse 'false' yap ve true döndür (unhide oldu)
    if (friendship.UserId == currentUserId && friendship.IsHiddenByFriendUserId)
    {
        friendship.IsHiddenByFriendUserId = false;
        await _context.SaveChangesAsync();
        return true; // ✅ Gerçekten unhide olduk
    }
    else if (friendship.FriendId == currentUserId && friendship.IsHiddenByFriendUserId)
    {
        friendship.IsHiddenByFriendUserId = false;
        await _context.SaveChangesAsync();
        return true; // ✅ Gerçekten unhide olduk
    }

    // (Eğer zaten 'false' ise false döndür - unhide gerekmedi)
    return false;
}
    }
}