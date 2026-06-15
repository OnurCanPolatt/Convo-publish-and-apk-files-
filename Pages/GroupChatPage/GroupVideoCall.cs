using Microsoft.JSInterop;
using Radzen;

namespace Convo.Shared.Pages.GroupChatPage
{
    public partial class GroupChatPanel
    {
     
#region videocall other users behave
public async void HandleFriendJoined(object? sender, (int roomId, Guid userId) data)
{
    try // ✅ try bloğu en dışarıya alındı
    {
        await InvokeAsync(async () =>
        {
            // ✅ 'groupMembers' null olsa bile '?. ' operatörü NRE'yi engeller (bu zaten iyi)
            var joinedUser = groupMembers?.FirstOrDefault(m => m.UserId == data.userId)?.User;
            var userName = joinedUser?.UserName ?? "Bilinmeyen kullanıcı";
            if (data.userId != myId)
            {
                statusMessage = $"{userName} konferansa katıldı.";
                await StatusMessge(statusMessage);
            }

            showWaitingCall = false;
            await InvokeAsync(StateHasChanged);
        });
    }
    catch (Exception ex)
    {
        Console.WriteLine($"HandleFriendJoined error: {ex.Message}");
    }
}
        private async void HandleJoinGroupConference(object? sender, (int roomId, Guid starterId,Guid groupId) data)
        {
            try
            {
            await InvokeAsync(async () =>
                {
                  
                        if (roomId != null && data.groupId == GroupId)
                        {
                            await JoinConference(data.roomId);
                        }
                        else
                            Console.WriteLine("Room number is null or group is not match.Therefore you can't join conference.Because there is no conference");
                    });
                }
                catch (Exception e)
            {
                Console.WriteLine(e);
                throw;
            }
        }
        // Konferans sonlandığında çağrılacak
        public async void HandleGroupConferenceEndedAsync(object sender, EventArgs e)
        {

            // 2. Bu component'in kendi UI durumunu temizle
            await InvokeAsync(async () =>
            {
                try
                {
                    isInVideoCall = false;
                    isMicMuted = false;
                    isCameraOff = false;
                    roomId = 0; // ✅ roomId'yi sıfırlamak kritik
                    showWaitingCall = false;
                    await InvokeAsync(StateHasChanged);
                    Console.WriteLine("✅ Konferansın bittiği bilgisi alındı, UI ve Servis durumu temizlendi.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"❌ HandleConferenceEnded hatası: {ex.Message}");
                }
            });
        }

        #endregion
        #region VideoCall
        private async Task StatusMessge(string statusMEssage)
        {
            NotificationService.Notify(new NotificationMessage
            {
                Severity = NotificationSeverity.Info,
                Summary = statusMessage,
                Duration = 4000
            });
        }
// GroupVideoCall.cs dosyasındaki bu metodu tamamen değiştirin.

private async Task StartVideoCall()
{
    // --- (Tüm güvenlik kontrolleriniz aynı kaldı) ---
    if (LayoutData == null || LayoutData.OnlineUsers == null)
    {
        statusMessage = "Online kullanıcı listesi henüz yüklenmedi...";
        await StatusMessge(statusMessage);
        return;
    }
    if (groupMembers == null || !groupMembers.Any())
    {
        statusMessage = "Grup üyeleri henüz yüklenmedi.";
        await StatusMessge(statusMessage);
        return;
    }
    if (myInfo == null)
    {
        statusMessage = "Kullanıcı bilgileri henüz yüklenmedi...";
        await StatusMessge(statusMessage);
        return;
    }
    var onlineMembers = groupMembers.Where(m =>
        m.IsActive &&
        m.UserId != myId &&
        LayoutData.OnlineUsers.Contains(m.UserId.ToString())).ToList();
    // if (!onlineMembers.Any())
    // {
    //     statusMessage = "Grupta çevrimiçi başka kullanıcı yok!";
    //     await StatusMessge(statusMessage);
    //     return;
    // }
    // --- (Kontroller bitti) ---

    try
    {
        showWaitingCall = true;
        isInVideoCall = true;
        await InvokeAsync(StateHasChanged);
        
        // Her zaman aynı oda ID'sini kullan
        var currentRoomId = Math.Abs(GroupId.GetHashCode());

            // --- 2. ODA YOK: Yeni Oda Oluştur (Eski Mantık) ---
            Console.WriteLine($"🎥 Yeni oda oluşturuluyor: {currentRoomId}");
            var roomCreated = await JSRuntime.InvokeAsync<bool>("createRoom", currentRoomId, myInfo.UserName);
            
            if (roomCreated)
            {
                statusMessage = "Grup görüşmesi başlatıldı!";
                await StatusMessge(statusMessage);

                // Servisi ve Hub'ı bilgilendir
                await _conferenceService.StartGroupConferenceAsync(currentRoomId.ToString(), myId.ToString(), groupInfo.Id);
            }
            else
            {
                statusMessage = "Grup görüşmesi başlatılamadı (createRoom hatası)";
                await StatusMessge(statusMessage);
                showWaitingCall = false;
                isInVideoCall = false;
            }
        
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Grup video call başlatma hatası: {ex.Message}");
        await LeaveConference(); // (Hata durumunda temizlik yap)
    }
}
private async Task JoinConference(int roomId)
{
    try
    {
        if (myInfo == null)
        {
            statusMessage = "Kullanıcı bilgileri henüz yüklenmedi. Konferansa katılamıyor.";
            await StatusMessge(statusMessage);
            return;
        }

        // ✅ Alıcının da hangi odada olduğunu bilmesi için roomId'yi ayarla
        this.roomId = roomId;

        isInVideoCall = true;
        await InvokeAsync(StateHasChanged);
        
        var result = await JSRuntime.InvokeAsync<bool>("joinRoom", roomId, myInfo.UserName);
        
        if (result)
        {
            await _conferenceService.JoinGroupConferenceAsync(roomId.ToString(), myId.ToString(), this.GroupId);
        }
        else
        {
            statusMessage = "Konferansa katılınamadı!";
            await StatusMessge(statusMessage);
            // ✅ HATA DÜZELTMESİ: Başarısız olursa durumu sıfırla
            isInVideoCall = false; 
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"JoinConference hatası: {ex.Message}");
        statusMessage = "Konferansa katılma hatası!";
        await StatusMessge(statusMessage);
        // ✅ HATA DÜZELTMESİ: Hata alırsan durumu sıfırla
        isInVideoCall = false;
    }

    await InvokeAsync(StateHasChanged);
}

private async Task LeaveConference()
{
    try
    {
        if (isInVideoCall)
        {
            // ✅ ADIM 1: GÜVENİLİR KAYNAKTAN (JANUS) KATILIMCI SAYISINI AL
            int participantCount = await JSRuntime.InvokeAsync<int>("getParticipantCount");
            
            bool isLastParticipant = participantCount <= 1; 

            // ✅ ADIM 2: MANTIĞI UYGULA
            if (isLastParticipant)
            {
                // --- SON KİŞİ: Odayı yok et ---
                Console.WriteLine("🏁 Son katılımcı ayrılıyor - Oda kapatılacak");
                statusMessage = "Konferans sonlandırılıyor...";
                await StatusMessge(statusMessage);
                
                await JSRuntime.InvokeVoidAsync("destroyAndLeaveRoom");
            }
            else
            {
                // --- ODADA BAŞKALARI VAR: Sadece ayrıl ---
                Console.WriteLine("👤 Odada başkaları var - Sadece ayrılınıyor");
                
                await JSRuntime.InvokeVoidAsync("leaveRoomOnly");
            }

            // ✅ ADIM 3: HUB'A BİLDİR (Fire-and-forget)
            _ = _conferenceService.LeaveGroupConferenceAsync(roomId.ToString(), myId.ToString(), isLastParticipant, this.GroupId);
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"LeaveConference hatası: {ex.Message}");
        statusMessage = "Konferandan ayrılma hatası";
        await StatusMessge(statusMessage);
    }
    finally
    {
        // 4. UI'ı ÖNCE temizle (video ekranını kapat)
        isInVideoCall = false;
        isMicMuted = false;
        isCameraOff = false;
        showWaitingCall = false;
        
        // 5. ✅ YENİ ADIM: UI temizlendikten sonra,
        // "Oda başkaları için hala aktif mi?" diye sunucuya tekrar sor.
        try
        {
            if (LayoutData?.IsSignalRReady == true)
            {
                // Sunucudaki GetActiveRoomForGroup'u tekrar çağır.
                // Eğer oda sonlandıysa (isLastParticipant) Hub 0 döndürecek.
                // Eğer oda devam ediyorsa Hub 12345 (roomId) döndürecek.
                this.roomId = await JSRuntime.InvokeAsync<int>("window.signalRManager.getActiveRoomForGroup", GroupId);
                
                if(this.roomId != 0)
                {
                    Console.WriteLine($"✅ Aramadan ayrıldım, ancak oda {this.roomId} hala aktif. 'Katıl' butonu gösterilecek.");
                }
                else
                {
                    Console.WriteLine($"✅ Aramadan ayrıldım ve oda sonlandı. 'Başlat' butonu gösterilecek.");
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Ayrıldıktan sonra oda durumu kontrol edilemedi: {ex.Message}");
            this.roomId = 0; // Hata durumunda sıfırla
        }

        // 6. UI'ı yeni 'roomId' bilgisiyle son kez güncelle.
        await InvokeAsync(StateHasChanged);
    }
}
        private async Task RejectConference()
        {
            statusMessage = "Konferans daveti reddedildi";
            await StatusMessge(statusMessage);
            await InvokeAsync(StateHasChanged);
            
        }

        private async Task ToggleMic()
        {
            try
            {
                var isEnabled = await JSRuntime.InvokeAsync<bool>("toggleMicrophone");
                isMicMuted = !isEnabled; // Tersini al
                await InvokeAsync(StateHasChanged);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ ToggleMic error: {ex.Message}");
            }
        }

        private async Task ToggleCamera()
        {
            try
            {
                var isEnabled = await JSRuntime.InvokeAsync<bool>("toggleCamera");
                isCameraOff = !isEnabled; // Tersini al
                await InvokeAsync(StateHasChanged);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ ToggleCamera error: {ex.Message}");
            }
        }
    }

    #endregion
}
