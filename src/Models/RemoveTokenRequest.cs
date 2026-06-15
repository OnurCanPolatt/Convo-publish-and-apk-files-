namespace Convo.Web.Models;

public class RemoveTokenRequest
{
    public Guid UserId { get; set; }
    public string Platform { get; set; } = "android";
}