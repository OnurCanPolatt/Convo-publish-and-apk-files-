using Microsoft.AspNetCore.SignalR;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Domain.Entities;

namespace Infrastructure.Hubs
{
    partial class NotificationHub
    {
        public async Task NotifyGroupConferenceStarted(string roomId, string starterId, string groupId)
        {
            Console.WriteLine("═══════════════════════════════════════");
            Console.WriteLine($"🎥 GRUP VIDEO CALL BAŞLATILIYOR");
            Console.WriteLine($"   RoomId: {roomId}");
            Console.WriteLine($"   StarterId: {starterId}");
            Console.WriteLine($"   GroupId: {groupId}");
            Console.WriteLine("═══════════════════════════════════════");

            if (int.TryParse(roomId, out var roomIdInt) && Guid.TryParse(groupId, out var groupGuid))
            {
                _activeGroupRooms[groupGuid] = roomIdInt;
                Console.WriteLine($"HUB: ✅ Oda {roomIdInt} aktif olarak KAYDEDİLDİ. Grup: {groupGuid}");
            }

            // SignalR ile online kullanıcılara gönder
            Console.WriteLine($"📡 SignalR: OthersInGroup({groupId}) gönderiliyor...");
            await Clients.OthersInGroup(groupId)
                .SendAsync("ReceiveGroupConferenceNotification", roomId, starterId, groupId);
            Console.WriteLine("✅ SignalR gönderimi tamamlandı");

            // ✅ YENİ: OFFLINE grup üyelerine FCM notification
            try
            {
                var groupMembers = await _groupService.GetGroupMemberIdsAsync(Guid.Parse(groupId));
                var groupInfo = await _groupService.GetGroupInfo(Guid.Parse(groupId));
                string groupName = groupInfo?.Name ?? "Grup";
                string callerName = await _userService.GetUserNameAsync(Guid.Parse(starterId));

                Console.WriteLine($"📋 Grup üye sayısı: {groupMembers.Count()}");

                foreach (var memberId in groupMembers)
                {
                    string memberIdStr = memberId.ToString();

                    // Kendine gönderme
                    if (memberIdStr.Equals(starterId, StringComparison.OrdinalIgnoreCase))
                    {
                        Console.WriteLine($"   ⏭️ Kendisine gönderim atlandı: {memberId}");
                        continue;
                    }

                    // ✅ DÜZELTME: IsUserReallyOnline metodunu kullan (case-insensitive ve temp disconnect kontrolü)
                    bool isOnline = IsUserReallyOnline(memberIdStr);

                    if (!isOnline)
                    {
                        Console.WriteLine($"   📱 OFFLINE üyeye FCM gönderiliyor: {memberId}");

                        await _fcmService.SendVideoCallNotificationAsync(
                            userId: memberId,
                            callerName: callerName,
                            roomId: roomId,
                            callerId: Guid.Parse(starterId),
                            isGroup: true,
                            groupId: Guid.Parse(groupId),
                            groupName: groupName
                        );
                    }
                    else
                    {
                        Console.WriteLine($"   ✅ ONLINE üye (SignalR ile gönderildi): {memberId}");
                    }
                }

            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Group video call FCM notification error: {ex.Message}");
            }
        }
        public async Task NotifyGroupUserJoined(string roomId, string userId, string groupId)
        {
            await Clients.OthersInGroup(groupId) 
                .SendAsync("ReceiveUserJoined", roomId, userId); 
        }
        public async Task NotifyGroupUserLeft(string roomId, string userId, string groupId)
        {
            await Clients.OthersInGroup(groupId) 
                .SendAsync("ReceiveUserLeft", roomId, userId);
        }
        public async Task NotifyGroupConferenceEnded(string roomId, string groupId)
        {
            if (Guid.TryParse(groupId, out var groupGuid))
            {
                // TryRemove kullanmak daha güvenlidir
                _activeGroupRooms.TryRemove(groupGuid, out _);
                Console.WriteLine($"HUB: ✅ Oda kaydı SİLİNDİ. Grup: {groupGuid}");
            }
            await Clients.OthersInGroup(groupId) 
                .SendAsync("ReceiveConferenceEnded", roomId); 
        }
    }
}
