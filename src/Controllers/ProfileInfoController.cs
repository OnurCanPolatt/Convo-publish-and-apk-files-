using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Domain.Interfaces;
using Convo.Web.Models;

namespace Convo.Web.Controllers;

[Authorize(AuthenticationSchemes = $"{JwtBearerDefaults.AuthenticationScheme},Identity.Application")]
[Route("api/[controller]")]
[ApiController]
public class ProfileInfoController:ControllerBase
{
    private readonly IUserService _userService;
    
    public ProfileInfoController(IUserService userService)
    {
        _userService = userService;
    }

    [HttpPut("update-allInfo")]
    public async Task<IActionResult> UpdateInfos([FromBody] ProfileDtoModel profile)
    {
        if (profile==null)
            return BadRequest(new { message = "E-posta boş olamaz." });

        try
        {
            var result = await _userService.UpdateUserProfileAsync(profile.email,
                profile.userName, profile.phone, profile.country, profile.city, profile.about);

            if (!result)
                return Conflict(new { message = "Bilgiler GÜNCELLENEMEDİ !!" });

            return Ok(new { message = "Bilgiler GÜNCELLENDİ." });
        }
        catch (FormatException)
        {
            return BadRequest(new { message = "Bilgilerin formatında bir yanlışlık var.." });
        }
        catch (Exception)
        {
            // logla
            return StatusCode(500,
                new { message = "Bilgiler güncellenirken bir teknik hata oluştu !!." });
        }
    }
    [HttpPut("change-password")]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest model)
    {
        if (string.IsNullOrWhiteSpace(model.CurrentPassword) || string.IsNullOrWhiteSpace(model.NewPassword))
            return BadRequest(new { message = "Şifre alanları boş olamaz." });

        if (model.NewPassword.Length < 6)
            return BadRequest(new { message = "Yeni şifre en az 6 karakter olmalıdır." });

        try
        {
            // Web'de kullandığınız IUserService içindeki metodu çağırıyoruz
            var success = await _userService.ChangePasswordAsync(model.CurrentPassword, model.NewPassword);

            if (success)
                return Ok(new { message = "Şifre başarıyla güncellendi." });

            return BadRequest(new { message = "Mevcut şifreniz hatalı veya bir sorun oluştu." });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = "İşlem sırasında bir hata oluştu." });
        }
    }
    

}