using Domain.Models.Download;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.JSInterop;
using Radzen;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.ProfilePage
{
    partial class ProfileComponent
    {
private async Task HandleFileSelected(InputFileChangeEventArgs e)
{
    if (e.File == null || currentUser?.Id == null) return;

    // 🚨 KRİTİK: currentUser nesnesi asenkron işlem sırasında dispose olabilir.
    // Bu yüzden ID'yi işlemin en başında sabit bir değişkene alıyoruz.
    var userIdToNotify = currentUser.Id.ToString();

    try
    {
        IsUploading = true;
        await InvokeAsync(StateHasChanged);

        // Dosya boyutu kontrolü (10MB)
        if (e.File.Size > 10 * 1024 * 1024)
        {
            NotificationService.Notify(new NotificationMessage { 
                Severity = NotificationSeverity.Warning, 
                Summary = "Dosya boyutu 10MB'dan küçük olmalıdır", 
                Duration = 4000 
            });
            return;
        }

        // Dosya tipi kontrolü
        var allowedTypes = new[] { "image/jpeg", "image/jpg", "image/png", "image/gif" };
        if (!allowedTypes.Contains(e.File.ContentType.ToLower()))
        {
            NotificationService.Notify(new NotificationMessage { 
                Severity = NotificationSeverity.Warning, 
                Summary = "Sadece JPG, PNG ve GIF formatları desteklenmektedir", 
                Duration = 4000 
            });
            return;
        }

        var fileInput = new FileInput
        {
            FileName = e.File.Name,
            ContentType = e.File.ContentType,
            Size = e.File.Size,
            OpenStream = (maxSize) => e.File.OpenReadStream(maxSize)
        };

        // Resim yükleme işlemini başlat
        var result = await ImageService.UploadImageAsync(currentUser.Id, fileInput);

        if (result.IsSuccess)
        {
            ProfileImageUrl = result.OriginalImageUrl;

            // ✅ MainLayout önbelleğini ve Sidebar gibi componentleri güncelle
            if (LayoutData != null)
            {
                LayoutData.ProfileImages[Guid.Parse(userIdToNotify)] = ProfileImageUrl;
                EventShop.TriggerUserInfoUpdated(); 
                
                // 🚀 MOBİL VE DİĞER WEB CİHAZLARI İÇİN:
                // Hub üzerindeki UserInfoUpdated metodunu tetikler.
                // Not: userIdToNotify string olarak gönderilmelidir.
                await JSRuntime.InvokeVoidAsync("window.signalRManager.userInfoUpdated", userIdToNotify);
            }

            await OnProfileUpdated.InvokeAsync();
            NotificationService.Notify(new NotificationMessage { 
                Severity = NotificationSeverity.Info, 
                Summary = "Profil fotoğrafı başarıyla güncellendi!", 
                Duration = 4000 
            });
        }
        else
        {
            NotificationService.Notify(new NotificationMessage { 
                Severity = NotificationSeverity.Warning, 
                Summary = $"Profil fotoğrafı yüklenemedi: {result.ErrorMessage}", 
                Duration = 4000 
            });
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Upload hatası: {ex.Message}");
        NotificationService.Notify(new NotificationMessage { 
            Severity = NotificationSeverity.Error, 
            Summary = $"Bir hata oluştu: {ex.Message}", 
            Duration = 4000 
        });
    }
    finally
    {
        IsUploading = false;
        await InvokeAsync(StateHasChanged);
    }
}

// ESKİ DeleteProfileImage metodunu SİLİN ve bunu YAPIŞTIRIN
private async Task DeleteProfileImage()
{
    try
    {
        if (currentUser?.Id == null) return;

        var confirmed = await JSRuntime.InvokeAsync<bool>("showConfirmDialog",
            "Profil fotoğrafını silmek istediğinizden emin misiniz?",
            "Profil resminiz silinecek!");

        if (!confirmed) return;

        var success = await ImageService.DeleteImageAsync(currentUser.Id);

        if (success)
        {
            ProfileImageUrl = "/images/default-avatar.png";
            
            // ✅ DEĞİŞİKLİK: MainLayout önbelleğini güncelle
            if (LayoutData != null)
            {
                LayoutData.ProfileImages[currentUser.Id] = ProfileImageUrl;
                EventShop.TriggerUserInfoUpdated(); // Diğer component'lere haber ver
            }

            await OnProfileUpdated.InvokeAsync();
            NotificationService.Notify(new NotificationMessage { Severity = NotificationSeverity.Info, Summary = $"Profil fotoğrafı silindi", Duration = 4000 });
        }
        else
        {
            NotificationService.Notify(new NotificationMessage { Severity = NotificationSeverity.Warning, Summary = $"Profil fotoğrafı silinemedi", Duration = 4000 });
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Silme hatası: {ex.Message}");
        NotificationService.Notify(new NotificationMessage { Severity = NotificationSeverity.Error, Summary = $"Bir hata oluştu: {ex.Message}", Duration = 4000 });
    }
}
    }
}
