namespace Convo.Web.Models;

public class UpdateMemberAdminRequest {
    public Guid ChatRoomId { get; set; }
    public Guid UserId { get; set; }
    public bool IsAdmin { get; set; }
}