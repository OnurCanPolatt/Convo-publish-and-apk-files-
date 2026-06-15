using Domain.Interfaces.MobileInterface;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[ApiController]
[Route("api/[controller]")]
public class RequestController : ControllerBase // Flutter tarafı 'Friend' beklediği için isimlendirme önemlidir
{
    private readonly ICoreFriendService _friendService;

    public RequestController(ICoreFriendService friendService)
    {
        _friendService = friendService;
    }
    // 1. Arkadaşlık İsteği Gönder
    [HttpPost("send-request/{targetUserId}")]
    public async Task<IActionResult> SendRequest(Guid targetUserId)
    {
        // Servisiniz içeride IUserService ile kimin gönderdiğini buluyor
        var result = await _friendService.SendFriendRequest(targetUserId);
        return result ? Ok(new { message = "İstek başarıyla gönderildi." }) : BadRequest();
    }

    // 2. İsteği Kabul Et
    [HttpPost("accept-request/{targetUserId}")]
    public async Task<IActionResult> AcceptRequest(Guid targetUserId)
    {
        var result = await _friendService.AcceptFriendRequest(targetUserId);
        return result ? Ok(new { message = "Arkadaşlık isteği kabul edildi." }) : BadRequest();
    }
    [HttpPost("reject-request/{targetUserId}")]
    public async Task<IActionResult> RejectRequest(Guid targetUserId)
    {
        var result = await _friendService.RejectFriendRequest(targetUserId);
        return result ? Ok(new { message = "İstek reddedildi." }) : BadRequest();
    }
    // 3. İsteği İptal Et veya Reddet (RemoveFriendRequest metodunu kullanır)
    [HttpPost("remove-request/{targetUserId}")]
    public async Task<IActionResult> RemoveRequest(Guid targetUserId)
    {
        var result = await _friendService.RemoveFriendRequest(targetUserId);
        return result ? Ok(new { message = "İstek kaldırıldı." }) : BadRequest();
    }

    // 4. Arkadaştan Çıkar
    [HttpPost("remove-friend/{targetUserId}")]
    public async Task<IActionResult> RemoveFriend(Guid targetUserId)
    {
        var result = await _friendService.RemoveFriend(targetUserId);
        return result ? Ok(new { message = "Arkadaşlıktan çıkarıldı." }) : BadRequest();
    }
    [HttpGet("my-requests/{userId}")]
    public async Task<IActionResult> GetMyRequests(Guid userId, [FromQuery] int pageNumber = 1, [FromQuery] int pageSize = 10)
    {
        // Not: Şu anki servis metodunuz sayfalama yapmıyor olsa bile 
        // controller'ın bu parametreleri kabul etmesi Flutter tarafındaki hata olasılığını azaltır.
        var requests = await _friendService.GetFriendRequestsForMobile(userId);
        return Ok(requests);
    }
}