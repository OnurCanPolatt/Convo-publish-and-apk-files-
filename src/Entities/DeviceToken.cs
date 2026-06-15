namespace Domain.Entities
{
    public class DeviceToken
    {
        public Guid Id { get; set; }
        public Guid UserId { get; set; }
        public string Token { get; set; } = string.Empty;
        public string Platform { get; set; } = "android"; // android veya ios
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime? UpdatedAt { get; set; }
        
        // Navigation property
        public AppUser User { get; set; } = null!;
    }
}