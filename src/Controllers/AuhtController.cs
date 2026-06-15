using Convo.Web.Models;
using Domain.Entities;
using Domain.Interfaces;
using Domain.Interfaces.MobileInterface;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Identity;


namespace Convo.Web.Controllers;

[Route("api/[controller]")]
[ApiController]
public class AuthController : ControllerBase
{
    private readonly IUserService _userService;
    private readonly ITokenService _tokenService;
    private readonly ILogger<AuthController> _logger;
    private readonly UserManager<AppUser> _userManager;
    private readonly IEmailService _emailService;
    private readonly IPasswordResetService _passwordResetService;

    public AuthController(IUserService userService, ITokenService tokenService, ILogger<AuthController> logger,UserManager<AppUser> userManager,IEmailService emailService,
        IPasswordResetService passwordResetService)
    {
        _userService = userService;
        _tokenService = tokenService;
        _logger = logger;
        _userManager = userManager;
        _emailService = emailService;
        _passwordResetService=passwordResetService;
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginViewModel request)
    {
        // 1. Kendi Servis Katmanınızdaki Metodu Çağırarak Kullanıcıyı Doğrula
        AppUser? user =
            await _userService.AuthenticateForJwtAsync(request.UsernameOrEmail,
                request.Password); // Bu metot kendi DB kontrolünüzü yapar

        if (user == null)
        {
            return Unauthorized(new { message = "Kullanıcı adı veya şifre hatalı." });
        }

        // 2. Token Servisini Kullanarak JWT Token'ı Oluştur
        string token = _tokenService.CreateToken(user);

        // 3. Token'ı ve Kullanıcı Bilgilerini Flutter'a Geri Gönder
        return Ok(new
        {
            Token = token,
            UserId = user.Id.ToString(),
            Username = user.UserName,
            firstname = user.FirstName,
            lastname = user.LastName,
            age = user.Age,
            email = user.Email,
            phoneNumber = user.PhoneNumber,
            country = user.Country,
            city = user.City,
            gender = user.Gender,
            about = user.About,
        });
    }
    // API/AuthController.cs

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterViewModel request)
    {
        // 1. Tuple geri dönüşünü parçalayarak alıyoruz (Deconstruction)
        var (success, message) = await _userService.RegisterUserAsync(
            request.FirstName,
            request.LastName,
            request.UserName,
            request.Email,
            request.Password,
            request.Gender,
            request.Age,
            request.PhoneNumber,
            request.Country,
            request.City
        );

        // 2. Başarı durumuna göre dönen mesajı kullanıyoruz
        if (success)
        {
            return Ok(new { message = "Hesap başarıyla oluşturuldu." });
        }
        else
        {
            // 🚩 'message' artık "Bu e-posta adresi zaten kullanımda" gibi detaylı bilgi içeriyor.
            return BadRequest(new { message = message });
        }
    }
    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword([FromBody] string email)
    {
        var user = await _userManager.FindByEmailAsync(email);
        if (user == null) return Ok(new { message = "Kod gönderildi." });

        // 🚀 KRİTİK DEĞİŞİKLİK: "Email" provider'ı sayısal kod üretir
        var code = _passwordResetService.GenerateCode(email);

        string mailBody = $@"<div style='font-family:Arial; padding:20px; border:1px solid #eee;'>
                        <h2>Şifre Sıfırlama</h2>
                        <p>Kodunuz: <b style='font-size:24px; color:#667eea;'>{code}</b></p>
                        </div>";

        await _emailService.SendEmailAsync(user.Email, "Şifre Sıfırlama Kodu", mailBody);
        return Ok(new { message = "Kod gönderildi." });
    }
    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordDto model)
    {
        var user = await _userManager.FindByEmailAsync(model.Email);
        if (user == null) return BadRequest();

        if (!_passwordResetService.ValidateCode(model.Email, model.Code))
            return BadRequest(new { message = "Kod hatalı." });

        var resetToken = await _userManager.GeneratePasswordResetTokenAsync(user);
        var result = await _userManager.ResetPasswordAsync(user, resetToken, model.NewPassword);
    
        return result.Succeeded ? Ok() : BadRequest(result.Errors);
    }
}