namespace Convo.Web.Models;

public class GetMessagesRequest
{
    public string senderId { get; set; }
    public string receiverId { get; set; }
}