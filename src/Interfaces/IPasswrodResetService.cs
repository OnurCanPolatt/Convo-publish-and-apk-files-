namespace Domain.Interfaces
{
    public interface IPasswordResetService
    {
        string GenerateCode(string email);
        bool ValidateCode(string email, string code);
    }
}