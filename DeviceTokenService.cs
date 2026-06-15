using Domain.Entities;
using Domain.Interfaces;
using Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace Infrastructure.Services
{
    public class DeviceTokenService : IDeviceTokenService
    {
        private readonly ApplicationDbContext _context;

        public DeviceTokenService(ApplicationDbContext context)
        {
            _context = context;
        }

        public async Task<bool> RegisterTokenAsync(Guid userId, string token, string platform)
        {
            try
            {
                var existingToken = await _context.DeviceTokens
                    .FirstOrDefaultAsync(x => x.UserId == userId && x.Platform == platform);

                if (existingToken != null)
                {
                    existingToken.Token = token;
                    existingToken.UpdatedAt = DateTime.UtcNow;
                }
                else
                {
                    var deviceToken = new DeviceToken
                    {
                        Id = Guid.NewGuid(),
                        UserId = userId,
                        Token = token,
                        Platform = platform
                    };
                    _context.DeviceTokens.Add(deviceToken);
                }

                await _context.SaveChangesAsync();
                return true;
            }
            catch (Exception)
            {
                return false;
            }
        }

        public async Task<bool> RemoveTokenAsync(Guid userId, string platform)
        {
            try
            {
                var token = await _context.DeviceTokens
                    .FirstOrDefaultAsync(x => x.UserId == userId && x.Platform == platform);

                if (token != null)
                {
                    _context.DeviceTokens.Remove(token);
                    await _context.SaveChangesAsync();
                }

                return true;
            }
            catch (Exception)
            {
                return false;
            }
        }

        public async Task<string?> GetTokenByUserIdAsync(Guid userId)
        {
            var deviceToken = await _context.DeviceTokens
                .FirstOrDefaultAsync(x => x.UserId == userId);

            return deviceToken?.Token;
        }

        public async Task<List<string>> GetTokensByUserIdAsync(Guid userId)
        {
            return await _context.DeviceTokens
                .Where(x => x.UserId == userId)
                .Select(x => x.Token)
                .ToListAsync();
        }
    }
}