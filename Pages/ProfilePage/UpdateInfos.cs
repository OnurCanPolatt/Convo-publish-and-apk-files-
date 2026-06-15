using Radzen;
using System.Threading.Tasks;

// .razor dosyanızla aynı namespace'i kullandığınızdan emin olun
namespace Convo.Shared.Pages.ProfilePage 
{
    // 'partial' anahtar kelimesi bu sınıfın .razor dosyasıyla birleşeceğini söyler
    public partial class ProfileComponent 
    {
        // Email güncelleme
        private async Task UpdateEmail(string newEmail)
        {
            // --- C# Validasyon ---
            if (string.IsNullOrWhiteSpace(newEmail) || !System.Net.Mail.MailAddress.TryCreate(newEmail, out _))
            {
                NotificationService.Notify(new NotificationMessage
                {
                    Severity = NotificationSeverity.Warning, // DÜZELTME
                    Summary = "Lütfen geçerli bir email adresi girin.",
                    Duration = 4000
                });
                return; // Hatalıysa işlemi durdur
            }
            // --- Validasyon Sonu ---

            try
            {
                IsUpdatingEmail = true;
                await InvokeAsync(StateHasChanged);

                // Servis metodunuzun adı farklıysa (örn: UpdateUserFieldAsync) ona göre değiştirin
                var success = await UserService.UpdateEmailAsync(newEmail); 

                if (success)
                {
                    NotificationService.Notify(new NotificationMessage
                    {
                        Severity = NotificationSeverity.Success,
                        Summary = "Email başarıyla güncellendi!",
                        Duration = 4000
                    });

                    await LoadCurrentUser();
                    await OnProfileUpdated.InvokeAsync();
                }
                else
                {
                    NotificationService.Notify(new NotificationMessage
                    {
                        Severity = NotificationSeverity.Error, // DÜZELTME
                        Summary = "Email güncellenirken bir hata oluştu. Bu email zaten kullanımda olabilir.",
                        Duration = 4000
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Email güncelleme hatası: {ex.Message}");
                NotificationService.Notify(new NotificationMessage
                {
                    Severity = NotificationSeverity.Error, // DÜZELTME
                    Summary = "Bir hata oluştu. Lütfen tekrar deneyin.",
                    Duration = 4000
                });
            }
            finally
            {
                IsUpdatingEmail = false;
                await InvokeAsync(StateHasChanged);
            }
        }

        // Username güncelleme
        private async Task UpdateUsername(string newUsername)
        {
            // --- C# Validasyon ---
            if (string.IsNullOrWhiteSpace(newUsername))
            {
                NotificationService.Notify(new NotificationMessage
                {
                    Severity = NotificationSeverity.Warning, // DÜZELTME
                    Summary = "Kullanıcı adı boş olamaz.",
                    Duration = 4000
                });
                return; // Hatalıysa işlemi durdur
            }
            // --- Validasyon Sonu ---

            try
            {
                IsUpdatingUsername = true;
                await InvokeAsync(StateHasChanged);

                var success = await UserService.UpdateUsernameAsync(newUsername);

                if (success)
                {
                    NotificationService.Notify(new NotificationMessage
                    {
                        Severity = NotificationSeverity.Success,
                        Summary = "Kullanıcı adı başarıyla güncellendi.",
                        Duration = 4000
                    });
                    await LoadCurrentUser();
                    await OnProfileUpdated.InvokeAsync();
                }
                else
                {
                    NotificationService.Notify(new NotificationMessage
                    {
                        Severity = NotificationSeverity.Error, // DÜZELTME
                        Summary = "Kullanıcı adı güncellenirken bir hata oluştu. Bu kullanıcı adı zaten kullanımda olabilir.",
                        Duration = 4000
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Username güncelleme hatası: {ex.Message}");
                NotificationService.Notify(new NotificationMessage
                {
                    Severity = NotificationSeverity.Error, // DÜZELTME
                    Summary = "Bir hata oluştu. Lütfen tekrar deneyin.",
                    Duration = 4000
                });
            }
            finally
            {
                IsUpdatingUsername = false;
                await InvokeAsync(StateHasChanged);
            }
        }

        // Şifre güncelleme
        private async Task UpdatePassword(string currentPass, string newPassword)
        {
            // --- C# Validasyon ---
            if (string.IsNullOrWhiteSpace(currentPass) || string.IsNullOrWhiteSpace(newPassword))
            {
                NotificationService.Notify(new NotificationMessage
                {
                    Severity = NotificationSeverity.Warning, // DÜZELTME
                    Summary = "Şifre alanları boş olamaz.",
                    Duration = 4000
                });
                return;
            }

            if (newPassword.Length < 6)
            {
                NotificationService.Notify(new NotificationMessage
                {
                    Severity = NotificationSeverity.Warning, // DÜZELTME
                    Summary = "Yeni şifre en az 6 karakter olmalıdır!",
                    Duration = 4000
                });
                return;
            }
            // --- Validasyon Sonu ---

            try
            {
                IsUpdatingPassword = true;
                await InvokeAsync(StateHasChanged);

                var success = await UserService.ChangePasswordAsync(currentPass, newPassword);

                if (success)
                {
                    NotificationService.Notify(new NotificationMessage
                    {
                        Severity = NotificationSeverity.Success,
                        Summary = "Şifre başarıyla güncellendi!",
                        Duration = 4000
                    });
                    currentPassword = string.Empty; 
                    tempPassword = string.Empty; 
                }
                else
                {
                    NotificationService.Notify(new NotificationMessage
                    {
                        Severity = NotificationSeverity.Error, // DÜZELTME
                        Summary = "Şifre güncellenirken bir hata oluştu. Mevcut şifrenizi kontrol edin.",
                        Duration = 4000
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Şifre güncelleme hatası: {ex.Message}");
                NotificationService.Notify(new NotificationMessage
                {
                    Severity = NotificationSeverity.Error, // DÜZELTME
                    Summary = "Bir hata oluştu. Lütfen tekrar deneyin.",
                    Duration = 4000
                });
            }
            finally
            {
                IsUpdatingPassword = false;
                await InvokeAsync(StateHasChanged);
            }
        }
    }
}