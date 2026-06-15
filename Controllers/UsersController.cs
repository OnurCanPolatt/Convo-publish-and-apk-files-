using Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Domain.Interfaces.HubInterface;
using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[Route("api/[controller]")]
[ApiController]
public class UsersController : ControllerBase
{
    private readonly IHubService _hubService;
    private readonly IFriendService _friendService;
    private readonly IUserService _userService;

    public UsersController(IUserService userService, IHubService hubservice, IFriendService friendService)
    {
        _hubService = hubservice;
        _userService = userService;
        _friendService = friendService;
    }

    [HttpGet("onlineUsersList")]
    public async Task<IActionResult> GetOnlineUsers()
    {
        try
        {
            string[] onlineUsers = await _hubService.GetReallyOnlineUsersListAsync();
            return Ok(onlineUsers);
        }
        catch (Exception ex) // Genel Exception türünü yakalamak
        {
            Console.Error.WriteLine($"Online kullanıcı listesi çekilirken hata oluştu: {ex.Message}");
            return StatusCode(500,
                new
                {
                    message = "Sunucu tarafında online kullanıcılar listesi çekilirken beklenmedik bir hata oluştu."
                });
        }
    }
    

    [HttpGet("discovery")]
    public async Task<IActionResult> GetDiscoveryUsers([FromQuery] int pageNumber, 
        [FromQuery] int pageSize, 
        [FromQuery] string? searchTerm)
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userIdClaim)) return Unauthorized();
        try
        {
            var currentUserId = Guid.Parse(userIdClaim);
            var result = await _userService.GetDiscoveryUsersAsync(pageNumber, pageSize,currentUserId,searchTerm);
            return Ok(result);
        }
        catch (Exception e)
        {
            return StatusCode(500, new { message = "Discovery hatası: " + e.Message });
        }
    }

    [HttpPost("getUserInfobyId")]
    public async Task<IActionResult> GetUserInfo([FromBody] string userId)
    {
        try
        {
            return Ok(await _userService.GetUserInfo(Guid.Parse(userId)));
        }
        catch (Exception e)
        {
            Console.WriteLine(e);
            return StatusCode(500,
                new { message = "Sunucu tarafında kullanıcı bilgisi çekilirken beklenmedik bir hata oluştu." });
        }
    }

    [HttpGet("getUserNameAsync")]
    public async Task<IActionResult> GetUserNameAsync(string userId)
    {
        try
        {
            return Ok(await _userService.GetUserNameAsync(Guid.Parse(userId)));
        }
        catch (Exception e)
        {
            Console.WriteLine(e);
            return StatusCode(500,
                new { message = "Sunucu tarafında kullanıcı adı çekilirken beklenmedik bir hata oluştu." });
        }
    }


    #region Friends States

    [HttpPost("sendFriendRequest")]
    public async Task<IActionResult> SendFriendRequest(string friendId)
    {
        try
        {
            var friends = await _friendService.SendFriendRequest(Guid.Parse(friendId));
            return Ok(friends);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Arkadaşlık isteği yollarken bir hata oluştu: {ex.Message}");
            return StatusCode(500, new { message = "Arkadaşlık isteği yollanırken bir hata oluştu." });
        }
    }

    [HttpPost("removeFriendRequest")]
    public async Task<IActionResult> RemoveFriendRequest(string friendId)
    {
        try
        {
            var friends = await _friendService.RemoveFriendRequest(Guid.Parse(friendId));
            return Ok(friends);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Arkadaşlık isteği geri çekilirken bir hata oluştu: {ex.Message}");
            return StatusCode(500, new { message = "Istek geri çekilirkenbir hata oluştu." });
        }
    }

    [HttpPost("acceptFriendRequest")]
    public async Task<IActionResult> AcceptFriendRequest(string friendId)
    {
        try
        {
            var friends = await _friendService.AcceptFriendRequest(Guid.Parse(friendId));
            return Ok(friends);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Arkadaşlık isteği kabul edilirken bir hata oluştu: {ex.Message}");
            return StatusCode(500, new { message = "Arkadaşlık isteği kabul edilirken bir hata oluştu." });
        }
    }

    [HttpGet("getMyFriends")]
    public async Task<IActionResult> GetMyFriends()
    {
        try
        {
            var friends = await _friendService.GetMyFriends();
            return Ok(friends);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Arkadaş listesi alınırken bir hata oluştu: {ex.Message}");
            return StatusCode(500,
                new { message = "Sunucu tarafında arkadaş listesi çekilirken beklenmedik bir hata oluştu." });
        }
    }

    #endregion
}