using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Identity;
using Domain.Entities; // AppUser burada olmalı
using System.ComponentModel.DataAnnotations;
using Domain.Interfaces;

namespace Convo.Web.Pages.Account
{
    public class ResetPasswordModel : PageModel
    {
        private readonly UserManager<AppUser> _userManager;
        private readonly IPasswordResetService _passwordResetService;
        public ResetPasswordModel(
            UserManager<AppUser> userManager,
            IPasswordResetService passwordResetService)
        {
            _userManager = userManager;
            _passwordResetService = passwordResetService;
        }


        // 🚀 DÜZELTME: HTML tarafındaki "Input.Email" yapısına uyması için bir inner class oluşturuyoruz
        [BindProperty]
        public ResetPasswordInputModel Input { get; set; }

        public class ResetPasswordInputModel
        {
            [Required]
            public string Email { get; set; }

            [Required]
            [StringLength(6, MinimumLength = 6)]
            public string Code { get; set; }

            [Required]
            [DataType(DataType.Password)]
            [MinLength(6)]
            public string NewPassword { get; set; }
        }

        public void OnGet(string email)
        {
            Input = new ResetPasswordInputModel { Email = email };
        }

        public async Task<IActionResult> OnPostAsync()
        {
            if (!ModelState.IsValid) return Page();

            var user = await _userManager.FindByEmailAsync(Input.Email);
            if (user == null) return RedirectToPage("/Index");

            // Cache'den kod doğrula
            if (_passwordResetService.ValidateCode(Input.Email, Input.Code))
            {
                var resetToken = await _userManager.GeneratePasswordResetTokenAsync(user);
                var result = await _userManager.ResetPasswordAsync(user, resetToken, Input.NewPassword);
            
                if (result.Succeeded)
                {
                    TempData["RegisterSuccess"] = "Şifreniz başarıyla değiştirildi.";
                    return RedirectToPage("/Account/Login");
                }

                foreach (var error in result.Errors)
                {
                    ModelState.AddModelError(string.Empty, error.Description);
                }
            }
            else
            {
                ModelState.AddModelError(string.Empty, "Kod hatalı veya süresi dolmuş.");
            }

            return Page();
        }
    }
}