using Domain.Entities;

namespace Domain.Interfaces.MobileInterface;

public interface ITokenService
{
    // Başarılı bir kullanıcıdan JWT Token'ı oluşturan metot
    string CreateToken(AppUser user);
}