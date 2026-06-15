using Convo.Domain.Entities;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Convo.Application.Common.Interfaces
{
    public interface IUserRepository
    {
        Task<List<AppUser>> GetAllUsersAsync();
        Task<AppUser?> GetUserByEmailAsync(string email);
        Task<AppUser?> GetUserByIdAsync(Guid userId);
        Task<AppUser?> GetUserByUserNameAsync(string userName);
        Task<bool> CheckPasswordAsync(AppUser user, string password);
    }
}