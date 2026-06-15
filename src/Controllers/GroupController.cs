using Convo.Web.Models;
using Domain.Entities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Domain.Interfaces;
using Microsoft.AspNetCore.SignalR; // ✅ SignalR için gerekli
using Infrastructure.Hubs;          // ✅ NotificationHub'ın bulunduğu namespace

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[Route("api/[controller]")]
[ApiController]
public class GroupController : ControllerBase
{
    private readonly IGroupService _groupService;
    private readonly IHubContext<NotificationHub> _hubContext; // ✅ Field olarak tanımla

    // Constructor'da enjekte et
    public GroupController(IGroupService groupService, IHubContext<NotificationHub> hubContext)
    {
        _groupService = groupService;
        _hubContext = hubContext;
    }

    [HttpPost("createGroup")]
    public async Task<IActionResult> CreateGroup([FromBody] ChatRoom chatRoom)
    {
        if (chatRoom == null)
            return BadRequest(new { message = "Grup bilgisi boş olamaz." });

        try
        {
            var result = await _groupService.CreateGroup(chatRoom);

            if (result)
            {
                // ✅ GRUP ÜYELERİNE HABER VER - YENİ GRUP OLUŞTURULDU
                // ÖNEMLI: Tüm gruba "ReceiveGroupCreated" gönder
                Console.WriteLine($"🆕 Grup oluşturuldu, tüm üyelere bildirim gönderiliyor - GroupId: {chatRoom.Id}");

                if (chatRoom.Members != null && chatRoom.Members.Any())
                {
                    foreach (var member in chatRoom.Members)
                    {
                        Console.WriteLine($"📤 ReceiveGroupCreated gönderiliyor -> UserId: {member.UserId}, GroupId: {chatRoom.Id}");
                        await _hubContext.Clients.User(member.UserId.ToString())
                                         .SendAsync("ReceiveGroupCreated", chatRoom.Id.ToString());
                    }
                }

                return Ok(new { message = "Grup başarıyla oluşturuldu." });
            }

            return BadRequest(new { message = "Grup oluşturulamadı." });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = "Sunucu hatası: " + ex.Message });
        }
    }
    [HttpPost("getMyGroups")]
    public async Task<IActionResult> GetMyGroups([FromBody] string userId)
    {
        try
        {
            var groups = await _groupService.GetMyGroups(Guid.Parse(userId));
            return Ok(groups);

        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Grup listesi alınırken bir hata oluştu: {ex.Message}");
            return StatusCode(500,
                new { message = "Sunucu tarafında grup listesi çekilirken beklenmedik bir hata oluştu." });
        }
    }
    [HttpGet("getFreshGroupInfo/{groupId}")]
    public async Task<IActionResult> GetFreshGroupInfo(Guid groupId) {
        try {
            var group = await _groupService.GetFreshGroupInfo(groupId);
            return Ok(group);
        } catch (Exception ex) {
            // 🚨 Buradaki hatayı Visual Studio "Output" veya "Console" sekmesinden oku
            Console.WriteLine($"FATAL ERROR: {ex.Message}"); 
            return StatusCode(500, ex.Message);
        }
    }
   // 1. Grup Adı ve Açıklamasını Güncelleme
[HttpPut("updateGroup/{groupId}")]
public async Task<IActionResult> UpdateGroup(Guid groupId, [FromBody] UpdateGroupRequest request)
{
    // 🚀 DÜZELTME: request içinden gelen ImageUrl parametresini servise ilet
    var success = await _groupService.UpdateGroupInfo(
        groupId, 
        request.Name, 
        request.Description, 
        request.ImageUrl ?? "" // Buradaki "" yerine request.ImageUrl gelmeli
    );
    
    if (success)
    {
            await _hubContext.Clients.Group(groupId.ToString()).SendAsync("ReceiveGroupUpdated", groupId.ToString());
        return Ok(new { success = true });
    }
    return BadRequest(new { message = "Grup güncellenemedi." });
}
// 2. Üye Yetkisini Değiştirme (Admin Yap / Üye Yap)
[HttpPut("updateMemberAdminStatus")]
public async Task<IActionResult> UpdateMemberAdminStatus([FromBody] UpdateMemberAdminRequest request)
{
    var success = await _groupService.UpdateMemberAdminStatus(request.ChatRoomId, request.UserId, request.IsAdmin);
    
    if (success)
    {
        // 🚀 SignalR: Rolü değişen kişiye ve diğerlerine haber ver
        await _hubContext.Clients.Group(request.ChatRoomId.ToString()).SendAsync("ReceiveGroupUpdated", request.ChatRoomId.ToString());
        return Ok(new { success = true });
    }
    return BadRequest(new { message = "Rol güncellenemedi." });
}

// 3. Gruptan Ayrılma VEYA Üye Atma
// Not: Hem kendi ayrılan hem de admin tarafından atılan kişi için aynı servis metodunu kullanıyoruz.
    [HttpPost("leaveGroup/{groupId}/{userId}")]
    public async Task<IActionResult> LeaveGroup(Guid groupId, Guid userId)
    {
        var success = await _groupService.LeaveGroup(groupId, userId);

        if (success)
        {
            // ✅ DOĞRU EVENT: Grup üyelerine ve ayrılan kişiye bildir
            await _hubContext.Clients.Group(groupId.ToString())
                .SendAsync("ReceiveUserLeftGroup", groupId.ToString(), userId.ToString());

            // ✅ Ayrılan kişiye özel olarak da bildir
            await _hubContext.Clients.User(userId.ToString())
                .SendAsync("ReceiveUserLeftGroup", groupId.ToString(), userId.ToString());

            return Ok(new { success = true });
        }
        return BadRequest(new { message = "Gruptan ayrılma işlemi başarısız." });
    }


// 4. Grubu Tamamen Silme
    [HttpDelete("deleteGroup/{groupId}")]
    public async Task<IActionResult> DeleteGroup(Guid groupId)
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userIdClaim)) return Unauthorized();

        var currentUserId = Guid.Parse(userIdClaim);
        var success = await _groupService.DeleteGroup(groupId, currentUserId);

        if (success)
        {
            // ✅ DOĞRU EVENT: Tüm grup üyelerine "grup silindi" bildir
            await _hubContext.Clients.Group(groupId.ToString())
                .SendAsync("ReceiveGroupDeleted", groupId.ToString());
            return Ok(new { success = true });
        }
        return BadRequest(new { message = "Grubu silme yetkiniz yok veya grup bulunamadı." });
    }

// GroupController.cs dosyasına ekleyin

[HttpPost("addMembers/{groupId}")]
public async Task<IActionResult> AddMembers(Guid groupId, [FromBody] List<Guid> userIds)
{
    try
    {
        var success = await _groupService.AddMembersToGroup(groupId, userIds);
        
        if (success)
        {
            // Mevcut grup üyelerine haber ver
            await _hubContext.Clients.Group(groupId.ToString())
                .SendAsync("ReceiveGroupUpdated", groupId.ToString());
            
            // Yeni eklenen kullanıcılara da haber ver (onlar için YENİ grup!)
            foreach (var userId in userIds)
            {
                Console.WriteLine($"📤 Yeni üye için ReceiveGroupCreated gönderiliyor -> UserId: {userId}, GroupId: {groupId}");
                await _hubContext.Clients.User(userId.ToString())
                    .SendAsync("ReceiveGroupCreated", groupId.ToString());
            }
            
            return Ok(new { success = true, message = "Üyeler başarıyla eklendi." });
        }
        
        return BadRequest(new { success = false, message = "Üyeler eklenemedi." });
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Üye ekleme hatası - GroupId: {groupId}-{ex.Message}");
        return StatusCode(500, new { success = false, message = ex.Message });
    }
}
}