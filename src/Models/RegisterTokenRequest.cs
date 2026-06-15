namespace Convo.Web.Models;

public class RegisterTokenRequest
{
    public Guid UserId { get; set; }
    public string Token { get; set; } = string.Empty;
    public string Platform { get; set; } = "android";
}
