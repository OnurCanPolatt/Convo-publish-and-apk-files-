using System.Text;
using System.Security.Claims; // Claim, ClaimTypes için
using Microsoft.IdentityModel.Tokens; // SymmetricSecurityKey, SigningCredentials için
using System.IdentityModel.Tokens.Jwt; // JwtSecurityToken, JwtRegisteredClaimNames için
using Domain.Entities;
using Microsoft.Extensions.Configuration;
using Domain.Interfaces.MobileInterface;

namespace Infrastructure.Services.Mobile;

public class TokenService : ITokenService
{
    private readonly IConfiguration _config;
    private readonly string _securityKey;
    private readonly string _issuer;
    private readonly string _audience;

    public TokenService(IConfiguration config)
    {
        _config = config;
        // appsettings.json dosyasından ayarları güvenli şekilde oku
        _securityKey = _config["JwtSettings:SecurityKey"];
        _issuer = _config["JwtSettings:Issuer"];
        _audience = _config["JwtSettings:Audience"];
    }

    public string CreateToken(AppUser user)
    {
        // 1. Token İçeriğini (Payload/Claims) Oluştur
        var claims = new List<Claim>
        {
            // Kullanıcının benzersiz kimliği (ID) ve adı
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(JwtRegisteredClaimNames.UniqueName, user.UserName),
            // İhtiyacınız varsa roller de eklenebilir: new Claim(ClaimTypes.Role, user.Role),
        };

        // 2. Gizli Anahtarı Kullanarak Kimlik Bilgisini (Credentials) Oluştur
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_securityKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        // 3. Token Tanımını Oluştur
        var token = new JwtSecurityToken(
            issuer: _issuer,
            audience: _audience,
            claims: claims,
            expires: DateTime.Now.AddMinutes(
                _config.GetValue<int>("JwtSettings:ExpirationMinutes")),
            signingCredentials: creds
        );

        // 4. Token'ı String olarak Seri Hale Getir
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}