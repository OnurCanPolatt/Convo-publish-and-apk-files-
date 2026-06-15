using Domain.Constants;
using Domain.Entities;
using Domain.Enums;
using Domain.FileDataType;
using Microsoft.AspNetCore.Components;
using Microsoft.JSInterop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.ChatPage
{
    public partial class ChatPanel : ComponentBase
    {
        // ✅ Dispose flag to prevent operations after disposal
        private bool _disposed = false;
        private bool _isSending = false;

        #region Text Messages
        
        private async Task SendTextMessage()
        {
            if (_disposed || _isSending || string.IsNullOrWhiteSpace(newMessage))
                return;

            _isSending = true;
            var messageContent = newMessage;
            newMessage = ""; 
    
            // ✅ KRITIK: Zamanı bir kere al ve her yerde aynısını kullan
            var currentTime = DateTime.UtcNow;
    
            try
            {
                var message = new Message
                {
                    Id = Guid.NewGuid(),
                    Content = messageContent,
                    Type = MessageType.Text,
                    SenderId = myId,
                    ReceiverId = UserId,
                    SentAt = currentTime, // ✅ Sabitlenmiş zaman
                    IsRead = true,
                    IsDeleted = false,
                };

                // 1. Önce listeye ekle (UI güncellemesi için)
                AddMessageSafely(message);
                await _cacheService.AddMessageToCacheAsync(message, myId, UserId);
        
                await InvokeAsync(StateHasChanged);
                _ = ScrollToBottom();

                // 2. DB kaydet
                await _messageService.SaveMessage(message);

                // 3. SignalR'a gönder - ISO 8601 formatında (milisaniye hassasiyetle)
                await JSRuntime.InvokeVoidAsync("window.signalRManager.sendMessage",
                    UserId, 
                    messageContent, 
                    null, 
                    MessageType.Text.ToString(), 
                    null, 
                    false, 
                    message.Id.ToString(),
                    currentTime.ToString("o")); // ✅ "o" formatı = roundtrip ISO 8601

                Console.WriteLine($"✅ Mesaj gönderildi: {message.Id}, SentAt: {currentTime:o}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Gönderim hatası: {ex.Message}");
                newMessage = messageContent;
            }
            finally
            {
                _isSending = false;
            }
        }
    public async void HandleReceiveMessage(object? sender, (Guid senderId, string messageContent, string? fileUrl, string messageType, long filesize, Guid? groupId, string messageId, Guid? receiverId, DateTime sentAt) data)
{
    if (_disposed || _isDisposing) return;
    if (UserId == Guid.Empty || myId == Guid.Empty) return;
    if (data.senderId == myId)
    {
        Console.WriteLine($"⚠️ Kendi mesajım filtrelendi: {data.messageId}");
        return;
    }

    try
    {
        // Duplicate kontrolü
        lock (_messagesLock)
        {
            if (!string.IsNullOrEmpty(data.messageId))
            {
                var msgIdStr = data.messageId.ToString().ToLower();
                if (_messages.Any(m => m.Id.ToString().ToLower() == msgIdStr))
                {
                    Console.WriteLine($"⚠️ Duplicate engellendi: {msgIdStr}");
                    return;
                }
            }
        }

        await InvokeAsync(async () =>
        {
            if (_disposed || _isDisposing || _messages == null) return;
            if (data.groupId != null) return; // Grup mesajı filtrele
            
            bool isMessageForMe = data.receiverId.HasValue 
                ? (data.receiverId == myId) 
                : (data.senderId == UserId);
            
            bool isCurrentChatOpen = (data.senderId == UserId);

            if (isMessageForMe)
            {
                var message = CreateMessage(data, isRead: isCurrentChatOpen);
                if (message == null) return;

                // ✅ KRITIK LOG: Gelen mesajın zamanını kontrol et
                Console.WriteLine($"📩 Alınan mesaj: {data.messageId}, SentAt: {data.sentAt:o}");

                if (isCurrentChatOpen)
                {
                    AddMessageSafely(message);

                    if (!_disposed && !_isDisposing)
                    {
                        StateHasChanged();
                        await Task.Delay(50);
                        await ScrollToBottom();
                    }
                }

                try
                {
                    await _cacheService.AddMessageToCacheAsync(message, myId, data.senderId);
                    await _messageService.SaveMessage(message);
                }
                catch (Exception ex) 
                {
                    Console.WriteLine($"⚠️ Cache/DB Hatası: {ex.Message}");
                }
            }
        });
    }
    catch (Exception ex)
    {
        Console.WriteLine($"❌ HandleReceiveMessage Hatası: {ex.Message}");
    }
}

        // Helper method with null safety
        private Message CreateMessage((Guid senderId, string messageContent, string? fileUrl, string messageType, long filesize, Guid? groupId, string messageId, Guid? receiverId, DateTime sentAt) data, bool isRead)
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

            // 2. Mesaj Nesnesini Oluştur
            var message = new Message
            {
                Id = Guid.TryParse(data.messageId, out var parsedGuid) ? parsedGuid : Guid.NewGuid(),
                SenderId = data.senderId,
                ReceiverId = myId,
                Content = data.messageContent ?? "",
                SentAt = data.sentAt.ToUniversalTime(), // ✅ GÜNCELLENDİ: Gelen zaman kullanılıyor
                IsRead = isRead,
                Type = msgType,
                FileUrl = data.fileUrl
            };

            // 3. Dosya Verisi Varsa FileData Nesnesini Doldur
            if (!string.IsNullOrEmpty(data.fileUrl))
            {
                var fileName = (data.messageContent ?? "")
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