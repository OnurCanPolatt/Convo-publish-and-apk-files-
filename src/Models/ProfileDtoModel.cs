using System.ComponentModel.DataAnnotations;

namespace Convo.Web.Models;

public class ProfileDtoModel
{
    [Required(ErrorMessage = "Soyisim zorunlu")]
    public string email { get; set; } = string.Empty;
    [Required]
    public string userName { get; set; } = string.Empty;
    [Required]
    public string phone { get; set; } = string.Empty;
    [Required]
    public string country { get; set; } = string.Empty;
    [Required]
    public string city { get; set; } = string.Empty;
    public string about { get; set; } = string.Empty;

}