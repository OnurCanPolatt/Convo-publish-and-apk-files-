using Domain.Entities;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.JSInterop;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;


namespace Convo.Shared.Pages.GroupChatPage
{
    partial class GroupChatPanel   
    {
        #region UI Helpers
        private string GetProfileImageStyle(string imageUrl)
        {
            if (string.IsNullOrEmpty(imageUrl) || imageUrl == "/images/default-avatar.png")
            {
                return "background-color: #E6E7ED;";
            }
            return $"background-image: url('{imageUrl}'); background-size: cover; background-position: center;";
        }

        private async Task ScrollToBottom()
        {
            try
            {
                string containerId = isInVideoCall ? "videoMessagesContainer" : "messagesContainer";
                await JSRuntime.InvokeVoidAsync("scrollToBottom", containerId);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Scroll to bottom hatası: {ex.Message}");
            }
        }

        private string GetSenderProfileImage(Guid senderId)
        {
            return memberProfileImages.GetValueOrDefault(senderId, "/images/default-avatar.png");
        }

        private AppUser GetMessageSender(Guid senderId)
        {
            var member = groupMembers?.FirstOrDefault(m => m.UserId == senderId);
            return member?.User;
        }
        #endregion
    }
}
