using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Components;
using Microsoft.JSInterop;
using Radzen;
using System;
using System.Threading.Tasks;

namespace Convo.Shared.Pages.ChatPage
{
    public partial class ChatPanel
    {
        #region Video Call Event Handlers

        // ✅ Safe async void event handler
        private async void HandleReceiveConferenceRequest(object? sender, (int roomId, Guid starterUserId) data)
        {
            if (_disposed || data.starterUserId != UserId)
                return;

            try
            {
                await InvokeAsync(async () =>
                {
                    if (_disposed)
                        return;
                    _disposed = true;
                    _isDisposing = true;

                    try
                    {
                        _locationChangingHandler?.Dispose();
                        Console.WriteLine($"✅ Joining conference: Room={data.roomId}");
                        await JoinConference(data.roomId);
                    }
                    catch (JSDisconnectedException)
                    {
                        Console.WriteLine("⚠️ Browser disconnected during conference join");
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"❌ Conference join error: {ex.Message}");
                    }
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ HandleReceiveConferenceRequest error: {ex.Message}");
            }
        }

        // ✅ Safe async void event handler
        private async void HandleFriendJoined(object? sender, (int userId, Guid conferenceId) data)
        {
            if (_disposed)
                return;

            Console.WriteLine($"👥 Friend joined event - User (int): {data.userId}, ConferenceId: {data.conferenceId}, My UserId (Guid): {UserId}");

            try
            {
                // ✅ conferenceId Guid'i UserId ile karşılaştır
                if (data.conferenceId == UserId)
                {
                    await InvokeAsync(async () =>
                    {
                        if (_disposed || userInfo == null)
                            return;

                        statusMessage = $"{userInfo.UserName} konferansa katıldı.";
                        await StatusMessage(statusMessage);
                        showWaitingCall = false;
                        InvokeAsync(StateHasChanged);


                        Console.WriteLine($"✅ Friend joined confirmed - hiding waiting status");
                    });
                }
                else
                {
                    Console.WriteLine($"⚠️ Friend joined event not for me (conferenceId: {data.conferenceId}, I am: {UserId})");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ HandleFriendJoined error: {ex.Message}");
            }
        }

        // ✅ Safe async void event handler
        private async void HandleP2pConferenceEnded(object? sender, EventArgs e)
        {
            if (_disposed)
                return;

            Console.WriteLine($"🏁 P2P conference ended event received");

            try
            {
                await InvokeAsync(async () =>
                {
                    if (_disposed)
                        return;

                    try
                    {
                        await EndCall();
                        showWaitingCall = false;
                        isInVideoCall = false;
                        isMicMuted = false;
                        isCameraOff = false;
                        InvokeAsync(StateHasChanged);
                        
                        await Task.Delay(300);
                        await ScrollToBottom();

                        Console.WriteLine($"✅ Conference ended - UI reset complete");
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"❌ Conference end cleanup error: {ex.Message}");
                    }
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ HandleP2pConferenceEnded error: {ex.Message}");
            }
        }

        #endregion

        #region VideoCall Methods

        // ✅ Typo fix: StatusMessge → StatusMessage
        private async Task StatusMessage(string statusText)
        {
            if (_disposed || NotificationService == null)
                return;

            try
            {
                await InvokeAsync(() =>
                {
                    if (_disposed)
                        return;

                    NotificationService.Notify(new NotificationMessage
                    {
                        Severity = NotificationSeverity.Info,
                        Summary = statusText,
                        Duration = 4000,
                        Payload = Guid.NewGuid().ToString()
                    });
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ StatusMessage error: {ex.Message}");
            }
        }

        private async Task StartVideoCall()
        {
            if (_disposed || JSRuntime == null || myInfo == null)
                return;

            // // ✅ Null-safe online check
            // if (LayoutData?.OnlineUsers?.Contains(UserId.ToString()) != true)
            // {
            //     statusMessage = "Kullanıcı çevrimiçi değil!";
            //     await StatusMessage(statusMessage);
            //     return;
            // }

            try
            {
                // 1️⃣ Layout değişimi
                showWaitingCall = true;
                isInVideoCall = true;
                InvokeAsync(StateHasChanged);

                // 2️⃣ DOM render olsun
                await Task.Delay(300);

                if (_disposed)
                    return;

                // 3️⃣ Oda oluştur
                roomId = Math.Abs((myId.ToString() + UserId.ToString()).GetHashCode());
                Console.WriteLine($"🎥 Creating room: {roomId}");
                currentCallPartnerId = UserId;

                // ✅ Safe Janus URL retrieval
                var host = HttpContextAccessor?.HttpContext?.Request.Host.Host;
                var isLocal = host == "localhost" || host == "127.0.0.1";

                var janusUrl = isLocal
                    ? Configuration?["Janus:HttpEndpoint"]
                    : Configuration?["Janus:ExternalHttpEndpoint"];

                if (string.IsNullOrEmpty(janusUrl))
                {
                    Console.WriteLine("❌ Janus URL not configured");
                    statusMessage = "Video görüşmesi yapılandırması eksik";
                    await StatusMessage(statusMessage);
                    isInVideoCall = false;
                    showWaitingCall = false;
                    InvokeAsync(StateHasChanged);
                    return;
                }

                Console.WriteLine($"🎥 Using Janus URL: {janusUrl}");

                var roomCreated = await JSRuntime.InvokeAsync<bool>("createRoom", roomId, myInfo.UserName, janusUrl);
                
                if (_disposed)
                    return;

                if (!roomCreated)
                {
                    statusMessage = "Video görüşmesi başlatılamadı";
                    await StatusMessage(statusMessage);
                    isInVideoCall = false;
                    showWaitingCall = false;
                    InvokeAsync(StateHasChanged);
                    return;
                }

                Console.WriteLine($"✅ Room created and publishing started");

                await Task.Delay(500);
                await ScrollToBottom();

                if (_disposed || JSRuntime == null)
                    return;

                Console.WriteLine($"📡 Sending conference notification - Room: {roomId}");
                await JSRuntime.InvokeVoidAsync("window.signalRManager.notifyConferenceStarted",
                    roomId.ToString(), myId.ToString(), UserId.ToString());
            }
            catch (JSDisconnectedException)
            {
                Console.WriteLine("⚠️ Browser disconnected during video call start");
                await CleanupFailedCall();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ StartVideoCall error: {ex.Message}");
                await CleanupFailedCall();
            }
        }

        private async Task JoinConference(int roomId)
        {
            if (_disposed || JSRuntime == null || myInfo == null)
                return;

            try
            {
                Console.WriteLine($"🔗 Joining conference - Room: {roomId}");

                // 1️⃣ Layout değişimi
                isInVideoCall = true;
                InvokeAsync(StateHasChanged);

                // 2️⃣ DOM render olsun
                await Task.Delay(300);

                if (_disposed)
                    return;

                // ✅ joinRoom publishing tamamlanana kadar bekliyor
                var result = await JSRuntime.InvokeAsync<bool>("joinRoom", roomId, myInfo.UserName);

                if (_disposed)
                    return;

                if (result)
                {
                    Console.WriteLine($"✅ Successfully joined and published - Room: {roomId}");
                    currentCallPartnerId = UserId;
                    // Publishing ve Janus bağlantısı için bekle
                    await Task.Delay(3000);

                    if (_disposed || JSRuntime == null)
                        return;

                    Console.WriteLine($"📡 Notifying friend joined: {myId} to starter: {UserId}");
                    await JSRuntime.InvokeVoidAsync("window.signalRManager.notifyUserJoined",
                        roomId.ToString(), myId.ToString(), UserId.ToString());
                }
                else
                {
                    Console.WriteLine($"❌ Failed to join conference - Room: {roomId}");
                    statusMessage = "Konferansa katılınamadı!";
                    await StatusMessage(statusMessage);
                    isInVideoCall = false;
                    InvokeAsync(StateHasChanged);
                }
            }
            catch (JSDisconnectedException)
            {
                Console.WriteLine("⚠️ Browser disconnected during conference join");
                isInVideoCall = false;
                InvokeAsync(StateHasChanged);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ JoinConference error: {ex.Message}");
                statusMessage = "Konferansa katılma hatası!";
                await StatusMessage(statusMessage);
                isInVideoCall = false;
                InvokeAsync(StateHasChanged);
            }
        }

        private async Task EndCall()
        {
            if (_disposed )
                return;

            try
            {
                await InvokeAsync(async () =>
                {
                    if (_disposed)
                        return;

                    try
                    {
                        Console.WriteLine($"🏁 Ending call - isInVideoCall: {isInVideoCall}");

                        if (isInVideoCall && JSRuntime != null)
                        {
                            // 1. SignalR bildirimi gönder
                            try
                            {
                                Console.WriteLine($"📡 Sending conference end notification to: {UserId}");
                                await JSRuntime.InvokeVoidAsync("window.signalRManager.notifyConferenceEnded",currentCallPartnerId.ToString());
                            }
                            catch (JSDisconnectedException)
                            {
                                Console.WriteLine("⚠️ SignalR disconnected during end notification");
                            }
                            catch (Exception signalREx)
                            {
                                Console.WriteLine($"❌ SignalR notification error: {signalREx.Message}");
                            }

                            // 2. JavaScript cleanup
                            try
                            {
                                await JSRuntime.InvokeVoidAsync("destroyAndLeaveRoom");
                            }
                            catch (JSDisconnectedException)
                            {
                                Console.WriteLine("⚠️ Browser disconnected during room cleanup");
                            }
                            catch (Exception jsEx)
                            {
                                Console.WriteLine($"❌ JavaScript cleanup error: {jsEx.Message}");
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"❌ Call end error: {ex.Message}");
                    }
                    finally
                    {
                        // Her durumda C# state'ini temizle
                        if (!_disposed)
                        {
                            isInVideoCall = false;
                            isMicMuted = false;
                            isCameraOff = false;
                            roomId = 0;
                            showWaitingCall = false;
                            InvokeAsync(StateHasChanged);

                            Console.WriteLine("✅ Call ended and state cleaned up");
                        }
                    }
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ EndCall outer error: {ex.Message}");
            }
        }

        private async Task ToggleMic()
        {
            if (_disposed || JSRuntime == null)
                return;

            try
            {
                var isEnabled = await JSRuntime.InvokeAsync<bool>("toggleMicrophone");
                
                if (!_disposed)
                {
                    isMicMuted = !isEnabled;
                    InvokeAsync(StateHasChanged);
                }
            }
            catch (JSDisconnectedException)
            {
                Console.WriteLine("⚠️ Browser disconnected during mic toggle");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ ToggleMic error: {ex.Message}");
            }
        }

        private async Task ToggleCamera()
        {
            if (_disposed || JSRuntime == null)
                return;

            try
            {
                var isEnabled = await JSRuntime.InvokeAsync<bool>("toggleCamera");
                
                if (!_disposed)
                {
                    isCameraOff = !isEnabled;
                    InvokeAsync(StateHasChanged);
                }
            }
            catch (JSDisconnectedException)
            {
                Console.WriteLine("⚠️ Browser disconnected during camera toggle");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ ToggleCamera error: {ex.Message}");
            }
        }

        // ✅ Helper method for cleanup on failed calls
        private async Task CleanupFailedCall()
        {
            if (_disposed)
                return;

            try
            {
                await EndCall();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠️ Cleanup error: {ex.Message}");
            }
        }

        #endregion
    }
}