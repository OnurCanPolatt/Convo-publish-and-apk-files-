namespace Domain.Interfaces
{
    public interface IDeviceTokenService
    {
        Task<bool> RegisterTokenAsync(Guid userId, string token, string platform);
        Task<bool> RemoveTokenAsync(Guid userId, string platform);
        Task<string?> GetTokenByUserIdAsync(Guid userId);
        Task<List<string>> GetTokensByUserIdAsync(Guid userId);
    }
}