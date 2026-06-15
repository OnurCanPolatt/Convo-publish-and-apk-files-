using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Domain.Interfaces;
using Domain.Interfaces.MobileInterface;
using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[ApiController]
[Route("api/[controller]")]
public class NotificationController : ControllerBase
{
    private readonly ICoreNotificationService _notificationService;

    public NotificationController(ICoreNotificationService notificationService)
    {
        _notificationService = notificationService;
    }

    // 1. Tüm Bildirimleri Getir
    [HttpGet("my-notifications")]
    public async Task<IActionResult> GetMyNotifications([FromQuery] int skip = 0)
    {
        var userIdStr = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userIdStr)) return Unauthorized();
    
        var userId = Guid.Parse(userIdStr);
    
        // Servis metodumuzu çağırıyoruz
        var (notifications, unreadCount) = await _notificationService.GetUserNotificationsForMobileAsync(userId,skip);
    
        // Flutter'ın beklediği Map yapısında dönüyoruz
        return Ok(new { 
            notifications = notifications, 
            unreadCount = unreadCount 
        });
    }

    // 2. Bekleyen Arkadaşlık İsteklerini Getir
    [HttpGet("my-requests")]
    public async Task<IActionResult> GetMyRequests()
    {
        var userId = Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value);
        var requests = await _notificationService.GetUserRequestsAsync(userId);
        var requestCount = await _notificationService.GetRequestCountAsync(userId);
        
        return Ok(new { requests, requestCount });
    }

    // 3. Bildirimleri Okundu İşaretle
    [HttpPost("mark-as-read")]
    public async Task<IActionResult> MarkAsRead([FromBody] List<Guid> ids)
    {
        var result = await _notificationService.MarkMultipleAsReadInDbAsync(ids);
        return result ? Ok() : BadRequest();
    }
    [HttpPost("deleteNotifications")]

    public async Task<IActionResult> DeleteNotifications([FromBody] List<Guid> ids)
    {
        await _notificationService.SoftDeleteNotificationsAsync(ids);
        return Ok();
    }       
    
    [HttpPost("deleteAllNotifications")]
    public async Task<IActionResult> DeleteAllNotifications([FromBody] string userId)
    {
        await _notificationService.SoftDeleteAllNotificationsAsync(Guid.Parse(userId));
        return Ok();
    }
    
        
}