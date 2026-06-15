using Microsoft.AspNetCore.SignalR;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Infrastructure.Hubs
{
    partial class NotificationHub
    {
    // ✅ DÜZELTME: Parametre tipleri ve gönderilen veri tutarlı
    public async Task NotifyConferenceStarted(string roomId, string starterId, string targetUserId)
    {
        Console.WriteLine($"📞 Conference started - Room: {roomId}, Starter: {starterId}, Target: {targetUserId}");

        bool sentViaSignalR = false; // ✅ YENİ: FCM kontrolü için flag

        if (_connectedUsers.TryGetValue(targetUserId, out var connectionIds))
        {
            Console.WriteLine($"📡 Sending to {connectionIds.Count} connection(s) for user: {targetUserId}");

            foreach (var connectionId in connectionIds.ToList())
            {
                try
                {
                    await Clients.Client(connectionId).SendAsync("ReceiveConferenceNotification",
                        roomId, starterId);
                    Console.WriteLine($"✅ Conference notification sent to connection: {connectionId}");
                    sentViaSignalR = true; // ✅ YENİ: SignalR ile gönderildi
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"❌ Failed to send to connection {connectionId}: {ex.Message}");
                }
            }
        }
        else
        {
            Console.WriteLine($"⚠️ User {targetUserId} not found in connected users");
        }
        // ✅ YENİ: OFFLINE → FCM Notification
        if (!sentViaSignalR)
        {
            try
            {
                string callerName = Context.User?.Identity?.Name ?? "Bir kullanıcı";

                await _fcmService.SendVideoCallNotificationAsync(
                    userId: Guid.Parse(targetUserId),
                    callerName: callerName,
                    roomId: roomId,
                    callerId: Guid.Parse(starterId),
                    isGroup: false
                );

                Console.WriteLine($"📱 P2P Video Call FCM notification sent to {targetUserId}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ FCM notification error: {ex.Message}");
            }
        }

    }

    // ✅ DÜZELTME: Sadece konferansı başlatan kişiye bildir, herkese değil
    public async Task NotifyUserJoined(string roomId, string joinedUserId, string targetUserId)
    {
        Console.WriteLine($"👥 User joined - Room: {roomId}, User: {joinedUserId}, Target: {targetUserId}");

        // ✅ Sadece konferansı başlatan kişiye (targetUserId) bildir
        if (_connectedUsers.TryGetValue(targetUserId, out var connectionIds))
        {
            Console.WriteLine($"📡 Notifying conference starter: {targetUserId}");

            foreach (var connectionId in connectionIds.ToList())
            {
                try
                {
                    await Clients.Client(connectionId).SendAsync("ReceiveUserJoined",
                        roomId, joinedUserId);
                    Console.WriteLine($"✅ Join notification sent to starter: {targetUserId}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"❌ Failed to notify starter {targetUserId}: {ex.Message}");
                }
            }
        }
        else
        {
            Console.WriteLine($"⚠️ Conference starter {targetUserId} not connected");
        }
    }

    public async Task NotifyConferenceEnded(string targetUserId)
    {
        Console.WriteLine($"🏁 Conference ended - Notifying: {targetUserId}");
        try
        {
            if (_connectedUsers.TryGetValue(targetUserId, out var connectionIds))
            {
                Console.WriteLine($"📡 Sending end notification to {connectionIds.Count} connection(s)");

                foreach (var connectionId in connectionIds.ToList())
                {
                    try
                    {
                        await Clients.Client(connectionId).SendAsync("ReceiveP2pEndNotification");
                        Console.WriteLine($"✅ End notification sent to connection: {connectionId}");
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"❌ Failed to send end notification: {ex.Message}");
                    }
                }
            }
            else
            {
                Console.WriteLine($"⚠️ Target user {targetUserId} not connected");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("P2P sonlandırma eventi fırlatılamadı.");
        }
    }
    }
}

