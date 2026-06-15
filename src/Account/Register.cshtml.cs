using Convo.Web.Models;
using Domain.Interfaces;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Radzen;

namespace Convo.Web.Pages.Account
{
    public class RegisterModel : PageModel
    {
        private readonly NotificationService _notificationService;
        private readonly IUserService _userService;

        public RegisterModel(
            NotificationService notificationService,
            IUserService userService)
        {
            _notificationService = notificationService;
            _userService = userService;
        }

        [BindProperty]
        public RegisterViewModel Input { get; set; } = new();

        public void OnGet()
        {
            // Sayfa ilk açılışı
        }

        public async Task<IActionResult> OnPostAsync()
        {
            if (!ModelState.IsValid)
            {
                var errors = ModelState.Values.SelectMany(v => v.Errors).Select(e => e.ErrorMessage);
                _notificationService.Notify(NotificationSeverity.Warning, "Uyarı!", string.Join(" ", errors));
                return Page();
            }

            var (success, message) = await _userService.RegisterUserAsync(
                Input.FirstName,
                Input.LastName,
                Input.UserName,
                Input.Email,
                Input.Password,
                Input.Gender,
                Input.Age,
                Input.PhoneNumber,
                Input.Country,
                Input.City
            );

            if (success)
            {
                TempData["RegisterSuccess"] = "Hesabınız oluşturuldu.";
                return Redirect("/Login");
            }
            else
            {
                // ✅ DB Kontrolü Sonrası Hata Mesajlarını Textbox Altına Bağlama
                if (message.Contains("kullanıcı adı"))
                {
                    ModelState.AddModelError("Input.UserName", message);
                }
                else if (message.Contains("e-posta") || message.Contains("Email"))
                {
                    ModelState.AddModelError("Input.Email", message);
                }
                else if (message.Contains("telefon"))
                {
                    ModelState.AddModelError("Input.PhoneNumber", message);
                }
                else
                {
                    // Beklenmedik bir hata olursa formun en üstünde göster
                    ModelState.AddModelError(string.Empty, message);
                }

                // Kullanıcıyı bilgilendirmek için Toast bildirimi kalabilir
                _notificationService.Notify(NotificationSeverity.Error, "Hata!", message);
        
                return Page(); 
            }
        }
    }
}