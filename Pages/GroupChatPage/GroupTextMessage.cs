using Domain.Entities;
using Domain.Enums;
using Domain.FileDataType;
using Microsoft.AspNetCore.Components;
using Microsoft.JSInterop;
using Domain.Interfaces;
using Microsoft.Extensions.DependencyInjection;

namespace Convo.Shared.Pages.GroupChatPage
{
    public partial class GroupChatPanel : ComponentBase
    {
        [Inject] private IServiceScopeFactory ScopeFactory { get; set; } = default!;
        #region Text Messages
   private async Task SendTextMessage()
{
    if (_isSending) return;
    if (string.IsNullOrWhiteSpace(newMessage)) return;

    _isSending = true;
    var messageContent = newMessage;
    newMessage = ""; // Input'u hemen temizle
    
    // ✅ KRITIK: Zamanı bir kere al ve her yerde aynısını kullan
    var currentTime = DateTime.UtcNow;
    
    try
    {
        // 1. Mesaj nesnesini hazırla
        var message = new Message
        {
            Id = Guid.NewGuid(),
            Content = messageContent,
            Type = MessageType.Text,
            SenderId = myId,
            ChatRoomId = GroupId,
            SentAt = currentTime // ✅ Sabitlenmiş zaman
        };

        // 2. Kendi ekranına anında ekle (kullanıcı gecikme hissetmesin)
        AddMessageSafely(message);
        await InvokeAsync(StateHasChanged);
        await Task.Delay(100);
        await ScrollToBottom();

        // 3. SignalR ile diğer üyelere ANINDA gönder - ISO 8601 formatında
        await JSRuntime.InvokeVoidAsync("window.signalRManager.sendMessage",
            GroupId, 
            messageContent, 
            null, 
            MessageType.Text.ToString(), 
            null, 
            true, 
            message.Id.ToString(),
            currentTime.ToString("o")); // ✅ "o" formatı = roundtrip ISO 8601
    
        // 4. Veritabanı ve Cache gibi YAVAŞ işleri ARKA PLANDA "ateşle ve unut"
        _ = Task.Run(async () =>
        {
            using var scope = ScopeFactory.CreateScope();
            var messageService = scope.ServiceProvider.GetRequiredService<IMessageService>();
            var cacheService = scope.ServiceProvider.GetRequiredService<ICacheService>();

            await messageService.SaveMessage(message);
            await cacheService.AddGroupMessageToCacheAsync(message, GroupId);
        
            Console.WriteLine($"✅ Grup mesajı arka planda kaydedildi: {message.Id}, SentAt: {currentTime:o}");
        });
    }
    catch (Exception ex)
    {
        Console.WriteLine($"❌ Grup mesaj gönderimi hatası: {ex.Message}");
        newMessage = messageContent; // Hata olursa geri yükle
    }
    finally
    {
        _isSending = false;
    }
}

      public async void HandleReceiveGroupMessage(object? sender, (Guid senderId, string messageContent, string fileUrl, string messageType, long filesize, Guid? groupId, string? messageId, Guid? receiverId, DateTime sentAt) data)
{
    try
    {
        // ✅ Kendi mesajımı filtrele
        if (data.senderId == myId)
        {
            Console.WriteLine($"⚠️ Kendi grup mesajım filtrelendi: {data.messageId}");
            return;
        }

        // Duplicate kontrolü
        lock (_messagesLock)
        {
            if (!string.IsNullOrEmpty(data.messageId))
            {
                var msgIdStr = data.messageId.ToString().ToLower();
                if (_messages.Any(m => m.Id.ToString().ToLower() == msgIdStr))
                {
                    Console.WriteLine($"⚠️ Duplicate grup mesajı engellendi: {msgIdStr}");
                    return;
                }
            }
        }

        await InvokeAsync(async () =>
        {
            if (data.groupId.HasValue)
            {
                var isCurrentGroupChat = (data.groupId.Value == GroupId);
                var message = CreateGroupMessage(data, isRead: isCurrentGroupChat);

                // ✅ KRITIK LOG: Gelen mesajın zamanını kontrol et
                Console.WriteLine($"📩 Grup mesajı alındı: {data.messageId}, SentAt: {data.sentAt:o}");

                if (isCurrentGroupChat)
                {
                    AddMessageSafely(message);
                    await InvokeAsync(StateHasChanged);
                    await Task.Delay(100);
                    await ScrollToBottom();
                }

                // ✅ CACHE İŞLEMİ İÇİN GÜVENLİ YAPI
                _ = Task.Run(async () =>
                {
                    using var scope = ScopeFactory.CreateScope();
                    var cacheService = scope.ServiceProvider.GetRequiredService<ICacheService>();
                    await cacheService.AddGroupMessageToCacheAsync(message, data.groupId.Value);
                    Console.WriteLine($"✅ Grup mesajı cache'e eklendi: {data.messageId}");
                });
            }
        });
    }
    catch (Exception ex)
    {
        Console.WriteLine($"❌ HandleReceiveGroupMessage hatası: {ex.Message}");
    }
}
private Message CreateGroupMessage((Guid senderId, string messageContent, string fileUrl, string messageType, long filesize, Guid? groupId, string messageId, Guid? receiverId, DateTime sentAt) data, bool isRead)
{
    // 1. Enum Dönüşümü (Mobil ve Web uyumlu)
    var msgType = MessageType.Text;
    if (!string.IsNullOrEmpty(data.messageType))
    {
        // 🚀 MOBİL İÇİN: Eğer veri bir sayıysa (örn: "0"), doğrudan cast et
        if (int.TryParse(data.messageType, out var typeIndex))
        {
            msgType = (MessageType)typeIndex;
        }
        // 💻 WEB İÇİN: Eğer veri metin ise (örn: "Text"), enum olarak parse et
        else if (Enum.TryParse<MessageType>(data.messageType, true, out var parsedType))
        {
            msgType = parsedType;
        }
    }

    var message = new Message
    {
        Id = !string.IsNullOrEmpty(data.messageId) ? Guid.Parse(data.messageId) : Guid.NewGuid(),
        SenderId = data.senderId,
        ChatRoomId = data.groupId.Value,
        Content = data.messageContent,
        SentAt = data.sentAt.ToUniversalTime(), // ✅ Gelen zaman kullanılıyor
        IsRead = isRead,
        Type = msgType,
        FileUrl = data.fileUrl
    };

    if (!string.IsNullOrEmpty(data.fileUrl))
    {
        var fileName = data.messageContent
            .Replace("🎵 ", "")
            .Replace("🎬 ", "")
            .Replace("🖼️ ", "")
            .Replace("📄 ", "")
            .Replace("📎 ", "");
            
        message.FileData = new FileData
        {
            FileName = fileName,
            FileType = msgType,
            FilePath = data.fileUrl,
            FileSize = data.filesize
        };
    }

    return message;
}
        #endregion
    }
}
