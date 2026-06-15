using Convo.Web.Models;
using Domain.Interfaces;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Radzen;

namespace Convo.Web.Pages.Account
{
    public class LoginModel : PageModel
    {
        private readonly IUserService _userService;

        public LoginModel(
            NotificationService notificationService,
            IUserService userService)
        {
            _userService = userService;
        }

        [BindProperty]
        public LoginViewModel Input { get; set; } = new();

        public IActionResult OnGet()
        {
            // Eğer kullanıcı zaten giriş yapmışsa home'a yönlendir
            if (User.Identity?.IsAuthenticated == true)
            {
                return Redirect("/home");
            }
            Input = new LoginViewModel();
            return Page();
        }

        public async Task<IActionResult> OnPostAsync()
        {
            // 1. Form validation
            if (!ModelState.IsValid)
            {
                return Page();
            }

            // 2. Infrastructure'dan login kontrolü - RememberMe dahil
            var success = await _userService.LoginUserAsync(
                Input.UsernameOrEmail,
                Input.Password,
                Input.RememberMe  // 🎯 RememberMe parametresi eklendi
            );

            // 3. Sonuca göre toast mesajı ve yönlendirme
            if (success)
            {
                return Redirect("/home?success=" + Uri.EscapeDataString("Başarıyla giriş yaptınız!"));
            }
            else
            {
                TempData["LoginError"] = $"Giriş Hatası! Kullanıcı adı/email veya şifre yanlış!";   
                // Şifreyi temizle (güvenlik)
                Input.Password = "";
                return Page(); // Aynı sayfaya geri dön
            }
        }
    }
}