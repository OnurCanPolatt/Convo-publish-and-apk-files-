using System.ComponentModel.DataAnnotations;
namespace Convo.Web.Models
{
    public class LoginViewModel
    {
        [Required(ErrorMessage = "Kullanıcı adı veya email zorunludur")]
        public string UsernameOrEmail { get; set; } = string.Empty;

        [Required(ErrorMessage = "Şifre zorunludur")]
        [DataType(DataType.Password)]
        public string Password { get; set; } = string.Empty;

        [Display(Name = "Beni Hatırla")]
        public bool RememberMe { get; set; }
    }
}
