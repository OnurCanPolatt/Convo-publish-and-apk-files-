using Domain.Entities;
using Domain.Models;

namespace Domain.Interfaces
{
    public interface IUserService
    {
        // Kullanıcı kaydetme
        Task<(bool Success,string Message)> RegisterUserAsync(string firstName, string lastName, string userName, string email, string password, string gender, int age,string phoneNumber
            ,string country,string city);
        // Kullanıcı girişi
        Task<bool> LoginUserAsync(string userNameOrEmail, string password,bool rememberMe);
        Task<AppUser?> AuthenticateForJwtAsync(string userNameOrEmail, string password);

        // Kullanıcı var mı kontrol
        Task<bool> IsUserExistsAsync(string userNameOrEmail);
        Task<AppUser?> GetCurrentUserAsync(); // Giriş yapmış kullanıcıyı getir
        Task<List<AppUser>> GetAllUsersAsync(); // Giriş yapmış kullanıcıyı getir
        Task<string> GetUserNameAsync(Guid userId);
        Task<AppUser> GetUserInfo(Guid userId);

        // Esnek güncelleme metodları
        Task<bool> UpdateUserFieldAsync(string fieldName, string newValue);
        Task<bool> UpdateEmailAsync(string newEmail);
        Task<bool> UpdateUsernameAsync(string newUsername);
        Task<bool> UpdateUserProfileAsync(string email,string phoneNumber,
            string username, string country, string city, string about); // Toplu güncelleme (opsiyonel)
        Task<bool> ChangePasswordAsync(string currentPassword, string newPassword);
        Task<UserPaginationResult> GetDiscoveryUsersAsync(int pageNumber, int pageSize,Guid currentUserId,string? searchTerm=null);


    }
}
