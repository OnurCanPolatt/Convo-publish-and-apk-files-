using System.ComponentModel.DataAnnotations;

namespace Convo.Web.Models
{
    public class RegisterViewModel
    {
        [Required(ErrorMessage = "Ad gereklidir")]
        [StringLength(50, ErrorMessage = "Ad en fazla 50 karakter olabilir")]
        public string FirstName { get; set; } = "";
        [Required(ErrorMessage = "Soyad gereklidir")]
        [StringLength(50, ErrorMessage = "Soyad en fazla 50 karakter olabilir")]
        public string LastName { get; set; } = "";

        [Required(ErrorMessage = "Kullanıcı adı gereklidir")]
        [StringLength(50, MinimumLength = 3, ErrorMessage = "Kullanıcı adı 3-50 karakter arası olmalı")]
        // ✅ Boşluk yasağı eklendi
        [RegularExpression(@"^\S+$", ErrorMessage = "Kullanıcı adı boşluk karakteri içeremez")]
        public string UserName { get; set; } = "";

        [Required(ErrorMessage = "Email gereklidir")]
        [EmailAddress(ErrorMessage = "Geçerli bir email adresi girin")]
        public string Email { get; set; } = "";

        [Required(ErrorMessage = "Şifre gereklidir")]
        [StringLength(100, MinimumLength = 6, ErrorMessage = "Şifre en az 6 karakter olmalı")]
        public string Password { get; set; } = "";

        [Required(ErrorMessage = "Cinsiyet seçimi gereklidir")]
        public string Gender { get; set; } = "";

        [Required(ErrorMessage = "Yaş gereklidir")]
        [Range(18, 120, ErrorMessage = "Yaş 18-120 arasında olmalı")]
        public int Age { get; set; }

        // ✅ 11 Haneli ve sadece rakam kontrolü (Flutter ile tam uyumlu)
        [Required(ErrorMessage = "Telefon numarası gereklidir")]
        [RegularExpression(@"^[0-9]{11}$", ErrorMessage = "Telefon numarası tam olarak 11 haneli rakam olmalıdır")]
        public string PhoneNumber { get; set; } = "";

        [Required(ErrorMessage = "Ülke gereklidir")]
        public string Country { get; set; } = "";

        [Required(ErrorMessage = "Şehir gereklidir")]
        public string City { get; set; } = "";
    }
}