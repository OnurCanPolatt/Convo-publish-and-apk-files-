namespace Convo.Web.Models;

public class UpdateGroupRequest {
    public string Name { get; set; }
    public string Description { get; set; }
    public string? ImageUrl { get; set; }
}