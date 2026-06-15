using Domain.Entities;
using Domain.Interfaces;
using Domain.Interfaces.ConferenceInterfaces;
using Microsoft.JSInterop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Infrastructure.Services.WebRtcService
{
    // ✅ YENİ, "DURUMSUZ" (STATELESS) VERSİYON
    public class ConferenceService : IConferenceService
    {
        private readonly IJSRuntime _jsRuntime;
        private readonly IUserService _userService;

        public ConferenceService(IJSRuntime jsRuntime, IUserService userService)
        {
            _jsRuntime = jsRuntime;
            _userService = userService;
        }

        public Task StartGroupConferenceAsync(string roomId, string starterId, Guid groupId)
        {
            try
            {
                // BEKLEMEYİ KALDIR: İşlemi arka plana at (fire-and-forget)
                _ = _jsRuntime.InvokeVoidAsync(
                    "window.signalRManager.notifyGroupConferenceStarted", 
                    roomId, 
                    starterId,
                    groupId.ToString()
                );
                Console.WriteLine($"✅ Grup konferans daveti gönderildi (beklemiyor): {roomId}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ StartGroupConference hatası: {ex.Message}");
                // Hata olsa bile ShowErrorAsync'i BEKLEMEYİN, yoksa metot Task döndürmez
                _ = ShowErrorAsync($"Konferans daveti gönderilemedi: {ex.Message}");
            }
    
            // Metot artık async olmadığı için hemen tamamlanmış bir Task döndür
            return Task.CompletedTask; 
        }

// ✅ DEĞİŞİKLİK: 'Guid groupId' parametresi eklendi
        public async Task JoinGroupConferenceAsync(string roomId, string userId, Guid groupId)
        {
            try
            {
                // Bu metodun TEK GÖREVİ katılımı bildirmektir
                await _jsRuntime.InvokeVoidAsync(
                    "window.signalRManager.notifyUserJoined",
                    roomId, 
                    userId,
                    groupId.ToString() // ✅ DEĞİŞİKLİK: groupId'yi JS'e gönder
                );
                Console.WriteLine($"✅ 'User Joined' bildirimi gönderildi: {roomId}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ JoinGroupConference hatası: {ex.Message}");
                await ShowErrorAsync($"Konferansa katılım bildirilemedi: {ex.Message}");
            }
        }

        // ✅ YENİ: Bu metot artık "isLastParticipant" parametresi alıyor
// ✅ DEĞİŞİKLİK: 'Guid groupId' parametresi eklendi
        public async Task LeaveGroupConferenceAsync(string roomId, string userId, bool isLastParticipant, Guid groupId)
        {
            try
            {
                if (isLastParticipant)
                {
                    // Son kullanıcıysak, "Konferans Bitti" sinyali gönder
                    Console.WriteLine("🏁 Son katılımcı ayrılıyor - 'Bitti' sinyali gönderiliyor.");
                    await _jsRuntime.InvokeVoidAsync(
                        "window.signalRManager.notifyGroupConferenceEnded", 
                        roomId,
                        groupId.ToString() // ✅ DEĞİŞİKLİK: groupId'yi JS'e gönder
                    );
                }
                else
                {
                    // Son kullanıcı değilsek, "Kullanıcı Ayrıldı" sinyali gönder
                    Console.WriteLine($"👤 Normal ayrılma - 'Ayrıldı' sinyali gönderiliyor.");
                    await _jsRuntime.InvokeVoidAsync(
                        "window.signalRManager.notifyGroupUserLeft", 
                        roomId, 
                        userId,
                        groupId.ToString() // ✅ DEĞİŞİKLİK: groupId'yi JS'e gönder
                    );
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ LeaveGroupConference hatası: {ex.Message}");
            }
        }

        // Utility Methods
        public async Task<bool> ShowConferenceInvitationAsync(string groupId, string starterUserId)
        {
            try
            {
                // Not: GetUserNameAsync bir Task<string> döndürür, bu yüzden 'await' eklenmeli
                var starterName = await _userService.GetUserNameAsync(Guid.Parse(starterUserId));

                var result = await _jsRuntime.InvokeAsync<bool>("showJanusConferenceInvitation",
                    groupId, starterUserId, starterName);

                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ ShowConferenceInvitation hatası: {ex.Message}");
                return false;
            }
        }
        
        private async Task ShowErrorAsync(string errorMessage)
        {
            try
            {
                await _jsRuntime.InvokeVoidAsync("showToast", errorMessage, "error");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Hata mesajı gösterilirken hata: {ex.Message}");
            }
        }
    }
}