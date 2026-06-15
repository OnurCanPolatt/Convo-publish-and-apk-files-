using Domain.Models.Dto;

namespace Domain.Models;

public class UserPaginationResult
{
    public List<DiscoveryUserDto> Users { get; set; }
    public int TotalCount { get; set; }
}