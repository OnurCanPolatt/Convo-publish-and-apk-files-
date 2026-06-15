using Domain.FileDataType;
using Microsoft.AspNetCore.SignalR;
using Domain.Entities;
using Domain.Enums;

namespace Infrastructure.Hubs
{
    partial class NotificationHub
    {
      public async Task SendMessage(
    Guid targetId,
    string newMessage,
    string fileUrl,
    string messageType,
    long? filesize,
    bool isGroupMessage = false,
    string? messageId = null,
    string? sentAt = null
)
{
    var senderId = GetUserIdFromConnection(Context.ConnectionId);
    if (senderId == "unknown") return;

    // 1️⃣ Client zamanı
    DateTime finalDate;
    if (!string.IsNullOrEmpty(sentAt) &&
        DateTime.TryParse(sentAt, null, System.Globalization.DateTimeStyles.RoundtripKind, out var parsed))
        finalDate = parsed.ToUniversalTime();
    else
        finalDate = DateTime.UtcNow;

    // 2️⃣ MessageType
    if (!Enum.TryParse(messageType, true, out MessageType msgTypeEnum))
        msgTypeEnum = MessageType.Text;

    // 3️⃣ Message obj
    var msgObj = new Message
    {
        Id = Guid.Parse(messageId ?? Guid.NewGuid().ToString()),
        SenderId = Guid.Parse(senderId),
        Content = newMessage,
        FileUrl = fileUrl,
        Type = msgTypeEnum,
        SentAt = finalDate,
        ChatRoomId = isGroupMessage ? targetId : null,
        ReceiverId = isGroupMessage ? null : targetId,
        FileSize = filesize
    };

    // 4️⃣ Cache
    try
    {
        if (isGroupMessage)
            await _cacheService.AddGroupMessageToCacheAsync(msgObj, targetId);
        else
            await _cacheService.AddMessageToCacheAsync(msgObj, Guid.Parse(senderId), targetId);
    }
    
    catch { }

    // 5️⃣ DAĞITIM
    if (isGroupMessage)
    {
        // 🔹 SignalR
        await Clients.OthersInGroup(targetId.ToString())
            .SendAsync("ReceiveMessage",
                Guid.Parse(senderId),
                newMessage,
                fileUrl,
                messageType,
                filesize ?? 0,
                targetId,
                messageId,
                null,
                finalDate);

        var groupInfo = await _groupService.GetGroupInfo(targetId);
        string groupTitle = groupInfo?.Name ?? "Grup Mesajı";
        string senderUserName = await _userService.GetUserNameAsync(Guid.Parse(senderId));

        var groupMembers = await _groupService.GetGroupMemberIdsAsync(targetId);
        foreach (var memberId in groupMembers)
        {
            if (memberId.ToString().ToLower() == senderId.ToLower()) continue;

            // 🔓 UNHIDE (eski commit)
            await _groupService.UnhideGroupChatAsync(targetId, memberId);

            // 📱 OFFLINE → FCM (eski commit mantığı)
            if (!_connectedUsers.ContainsKey(memberId.ToString().ToLower()))
            {
                await _fcmService.SendNotificationAsync(
                    userId: memberId,
                    title: groupTitle,
                    body: $"{senderUserName} - {newMessage}",
                    senderId: targetId,   // 👈 Grup ID
                    isGroup: true,
                    targetName: "Grup"
                );
            }
        }
    }
    else
    {
        // 🔓 UNHIDE (eski commit)
        await _friendService.UnhidePrivateChatAsync(targetId, Guid.Parse(senderId));

        var targetKey = targetId.ToString().ToLower();
        bool sentViaSignalR = false;

        // 🔹 SignalR
        if (_connectedUsers.TryGetValue(targetKey, out var connectionIds))
        {
            foreach (var connId in connectionIds.ToList())
            {
                await Clients.Client(connId).SendAsync(
                    "ReceiveMessage",
                    Guid.Parse(senderId),
                    newMessage,
                    fileUrl,
                    messageType,
                    filesize ?? 0,
                    null,
                    messageId,
                    targetId,
                    finalDate);

                sentViaSignalR = true;
            }
        }

        // 📱 OFFLINE → FCM (eski commit birebir)
        if (!sentViaSignalR)
        {
            string senderName = Context.User?.Identity?.Name ?? "Bir kullanıcı";

            await _fcmService.SendNotificationAsync(
                userId: targetId,
                title: senderName,
                body: newMessage,
                senderId: Guid.Parse(senderId), // 👈 Flutter’ın id olarak okuduğu
                isGroup: false,
                targetName: senderName
            );
        }
    }
}
    }
}