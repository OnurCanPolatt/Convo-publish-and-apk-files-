using Convo.Web.Models;
using Domain.Entities;
using Domain.Interfaces;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;

using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[Route("api/[controller]")]
[ApiController]
public class MessageController:ControllerBase
{
    private readonly IMessageService _messageService;
    private readonly IFriendService _friendService;
    private readonly IGroupService _groupService;

    public MessageController(IMessageService messageService, IFriendService friendService, IGroupService groupService)
    {
        _messageService = messageService;
        _friendService = friendService;
        _groupService = groupService;
    }

    [HttpPost("saveMessage")]                       
    public async Task<IActionResult> SaveMessageAsync(Message message)
    {
        try
        {
            var result=await _messageService.SaveMessage(message);
            return Ok(result);
        }
        catch (Exception e)
        {
            Console.WriteLine(e);
            return StatusCode(500,
                new { message = "Mesaj db'ye kaydolurken bir hata oluştu." });
        }
    }    
    [HttpPost("getMessages")]
    public async Task<IActionResult> GetMessageAsync([FromBody] GetMessagesRequest request)
    {
        try
        {
            var result=await _messageService.GetMessagesAsync(Guid.Parse(request.senderId), Guid.Parse(request.receiverId));
            return Ok(result);
        }
        catch (Exception e)
        {
            Console.WriteLine(e);
            return StatusCode(500,
                new { message = "Mesajlar çekilirken bir hata oluştu." });
        }
    }    
    [HttpPost("getGroupMessages")]
    public async Task<IActionResult> GetGroupMessageAsync([FromBody] GroupMessagesRequest request)
    {
        try
        {
            var result=await _messageService.GetGroupMessagesAsync(Guid.Parse(request.GroupId));
            return Ok(result);
        }
        catch (Exception e)
        {
            Console.WriteLine(e);
            return StatusCode(500,
                new { message = "Grup Mesajları çekilirken bir hata oluştu." });
        }
    }
    [HttpPost("HidePrivateChat")]
    public async Task<IActionResult> HidePrivateChat([FromBody] HidePrivateChatRequest request)
    {
        try
        {
            // Token'dan işlemi yapan kullanıcının ID'sini alıyoruz
            var currentUserId = Guid.Parse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value);
            await _friendService.HidePrivateChatAsync(request.FriendId, currentUserId);
            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    // --- P2P Sohbet Gösterme ---
    [HttpPost("UnhidePrivateChat")]
    public async Task<IActionResult> UnhidePrivateChat([FromBody] HidePrivateChatRequest request)
    {
        try
        {
            var currentUserId = Guid.Parse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value);
            bool wasUnhidden = await _friendService.UnhidePrivateChatAsync(request.FriendId, currentUserId);
            return Ok(new { success = true, wasUnhidden = wasUnhidden });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    // --- Grup Sohbeti Gizleme ---
    [HttpPost("HideGroupChat")]
    public async Task<IActionResult> HideGroupChat([FromBody] HideGroupRequest request)
    {
        try
        {
            var currentUserId = Guid.Parse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value);
            await _groupService.HideGroupChatAsync(request.GroupId, currentUserId);
            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    // --- Grup Sohbeti Gösterme ---
    [HttpPost("UnhideGroupChat")]
    public async Task<IActionResult> UnhideGroupChat([FromBody] HideGroupRequest request)
    {
        try
        {
            var currentUserId = Guid.Parse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value);
            bool wasUnhidden = await _groupService.UnhideGroupChatAsync(request.GroupId, currentUserId);
            return Ok(new { success = true, wasUnhidden = wasUnhidden });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
