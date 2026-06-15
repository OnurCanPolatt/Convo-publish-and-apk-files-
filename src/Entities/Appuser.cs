using Microsoft.AspNetCore.Identity;
namespace Domain.Entities
{
    public class AppUser : IdentityUser<Guid>
    {
        public string FirstName { get; set; } = string.Empty;
        public string LastName { get; set; } = string.Empty;
        public int Age { get; set; }
        public string Gender { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime? LastSeenAt { get; set; }
        public string? About { get; set; }
        public bool IsActive { get; set; } = true;
        public string Country { get; set; } = string.Empty;
        public string City { get; set; } = string.Empty;

    }
}
