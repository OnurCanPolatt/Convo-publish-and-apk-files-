using Domain.MobilEnums;

namespace Domain.Models.Dto;

public class DiscoveryUserDto
{
    public string Id { get; set; }
    public string FirstName { get; set; }
    public string LastName { get; set; }
    public string UserName { get; set; }
    public int Age { get; set; }
    public string Gender { get; set; }
    public string? City { get; set; }
    public string? ProfileImageUrl { get; set; } // Minio'dan gelen link buraya girecek
    public FriendshipStatus Status { get; set; }
}