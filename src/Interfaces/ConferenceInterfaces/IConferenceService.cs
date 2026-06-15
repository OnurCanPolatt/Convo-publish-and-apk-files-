using System;
using System.Threading.Tasks;
using Domain.Entities;

namespace Domain.Interfaces.ConferenceInterfaces
{
    public interface IConferenceService
    {
        // ❌ DURUM (STATE) ÖZELLİKLERİ KALDIRILDI
        // (IsConferenceActive, ConferenceParticipants, vb. silindi)

        // ❌ HUB EVENT HANDLER METOTLARI KALDIRILDI
        // (HandleUserJoined, HandleUserLeft, ClearConferenceData, vb. silindi)

        // ✅ SADECE BU 4 METOT KALDI:

        /// <summary>
        /// Aramayı başlatan daveti SignalR Hub'a gönderir.
        /// </summary>
        Task StartGroupConferenceAsync(string roomId, string starterId, Guid groupId);

        /// <summary>
        /// Odaya katıldığını SignalR Hub'a bildirir.
        /// </summary>
        Task JoinGroupConferenceAsync(string roomId, string userId, Guid groupId);
        /// <summary>
        /// Odadan ayrıldığını SignalR Hub'a bildirir.
        /// </summary>
        /// <param name="isLastParticipant">Eğer 'true' ise, Hub'a "oda bitti" sinyali gönderir.</param>
        Task LeaveGroupConferenceAsync(string roomId, string userId, bool isLastParticipant, Guid groupId);        
        /// <summary>
        /// Alıcı tarafta (MainLayout) "Katıl/Reddet" SweetAlert'ini gösterir.
        /// </summary>
        Task<bool> ShowConferenceInvitationAsync(string groupId, string starterUserId);
    }
}