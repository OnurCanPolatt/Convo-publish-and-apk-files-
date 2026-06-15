using System.Net;
using System.Net.Mail;
using Domain.Interfaces; 
using Microsoft.Extensions.Configuration;

namespace Infrastructure.Services
{
    public class EmailService : IEmailService
    {
        private readonly IConfiguration _config;

        public EmailService(IConfiguration config)
        {
            _config = config;
        }

        public async Task SendEmailAsync(string toEmail, string subject, string message)
        {
            try
            {
                // 🚀 Verileri appsettings.json dosyasından çekiyoruz
                var smtpServer = _config["EmailSettings:SmtpServer"];
                var smtpPort = int.Parse(_config["EmailSettings:Port"] ?? "587");
                var senderEmail = _config["EmailSettings:Sender"];
                var appPassword = _config["EmailSettings:Password"];

                using (var client = new SmtpClient(smtpServer, smtpPort))
                {
                    client.EnableSsl = true;
                    client.DeliveryMethod = SmtpDeliveryMethod.Network;
                    client.UseDefaultCredentials = false;
                    client.Credentials = new NetworkCredential(senderEmail, appPassword);

                    var mailMessage = new MailMessage
                    {
                        // "Convo Destek" kısmı mail kutusunda gönderici adı olarak görünür
                        From = new MailAddress(senderEmail!, "Convo Destek"),
                        Subject = subject,
                        Body = message,
                        IsBodyHtml = true 
                    };

                    mailMessage.To.Add(toEmail);

                    await client.SendMailAsync(mailMessage);
                    Console.WriteLine($"✅ Mail başarıyla gönderildi: {toEmail}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Email gönderim hatası: {ex.Message}");
                // Uygulamanın çökmemesi ama hatayı bilmemiz için fırlatıyoruz
                throw new Exception("E-posta gönderilirken bir teknik hata oluştu.", ex);
            }
        }
    }
}