using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.GroupChatPage
{
    partial class GroupChatPanel
    {
        private async void HandleUpdateGroupInfo(object? sender, EventArgs e)
        {
            try 
            {
                // 1. Güncel veriyi çek
                var freshGroup = await _groupService.GetFreshGroupInfo(GroupId);

                // 2. Grup silinmişse (null) veya pasifse
                if (freshGroup == null || !freshGroup.IsActive)
                {
                    // 🚨 SADECE EĞER BU GRUBUN SAYFASINDAYSAK YÖNLENDİR
                    var currentUrl = NavigationManager.Uri;
                    if (currentUrl.Contains($"/groupChat/{GroupId}") || currentUrl.Contains($"/groupInfo/{GroupId}"))
                    {
                        Console.WriteLine("📢 Aktif grup silindi, ana sayfaya yönlendiriliyorsunuz...");
                        NavigationManager.NavigateTo("/home");
                    }
                    return;
                }

                // 3. Grup hala varsa sadece verileri yenile (Navigate etme!)
                await LoadGroupData();
                await InvokeAsync(StateHasChanged);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ HandleUpdateGroupInfo hatası: {ex.Message}");
            }
        }
    }

    }

