using Convo.Web.Models;
using Domain.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace Convo.Web.Controllers;

[Route("api/[controller]")]
[ApiController]
public class DeviceTokenController : ControllerBase
{
    private readonly IDeviceTokenService _deviceTokenService;

    public DeviceTokenController(IDeviceTokenService deviceTokenService)
    {
        _deviceTokenService = deviceTokenService;
    }

    [HttpPost("register")]
    public async Task<IActionResult> RegisterToken([FromBody] RegisterTokenRequest request)
    {
        var result = await _deviceTokenService.RegisterTokenAsync(
            request.UserId, 
            request.Token, 
            request.Platform);

        if (result)
            return Ok(new { message = "Token kaydedildi." });
        
        return BadRequest(new { message = "Token kaydedilemedi." });
    }

    [HttpDelete("remove")]
    public async Task<IActionResult> RemoveToken([FromBody] RemoveTokenRequest request)
    {
        var result = await _deviceTokenService.RemoveTokenAsync(request.UserId, request.Platform);

        if (result)
            return Ok(new { message = "Token silindi." });
        
        return BadRequest(new { message = "Token silinemedi." });
    }
}

