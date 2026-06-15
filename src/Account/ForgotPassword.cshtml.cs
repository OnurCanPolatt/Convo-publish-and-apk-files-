using Domain.Entities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Domain.Interfaces;
using Infrastructure.Services;
using Microsoft.AspNetCore.Identity;

namespace Convo.Web.Pages.Account
{
    public class ForgotPasswordModel : PageModel
    {
        private readonly UserManager<AppUser> _userManager;
        private readonly IEmailService _emailService;
        private readonly IPasswordResetService _passwordResetService;

        public ForgotPasswordModel(
            UserManager<AppUser> userManager, 
            IEmailService emailService,
            IPasswordResetService passwordResetService)
        {
            _userManager = userManager;
            _emailService = emailService;
            _passwordResetService = passwordResetService;
        }

        [BindProperty]
        public string Email { get; set; }

        public async Task<IActionResult> OnPostAsync()
        {
            if (string.IsNullOrEmpty(Email)) return Page();

            var user = await _userManager.FindByEmailAsync(Email);
            if (user != null)
            {
                // 6 haneli kod üret ve cache'e kaydet
                var code = _passwordResetService.GenerateCode(Email);
            
                string mailBody = $@"<div style='font-family:Arial; padding:20px;'>
                <h2>Şifre Sıfırlama</h2>
                <p>Kodunuz: <b style='font-size:24px; color:#667eea;'>{code}</b></p>
                <p>Bu kod 15 dakika geçerlidir.</p>
            </div>";
            
                await _emailService.SendEmailAsync(user.Email!, "Şifre Sıfırlama Kodu", mailBody);
            }

            return RedirectToPage("/Account/ResetPassword", new { email = Email });
        }
    }
}