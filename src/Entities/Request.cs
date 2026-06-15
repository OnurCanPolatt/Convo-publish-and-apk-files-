using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Domain.Enums;

namespace Domain.Entities
{
    public class Request
    {
        public Guid Id { get; set; }
        public Guid SenderId { get; set; }     
        public Guid ReceiverId { get; set; }
        public DateTime SentAt { get; set; }
        public RequestType RequestType { get; set; }
        public DateTime? ResponsedAt { get; set; }

        // Navigation properties
        public AppUser Sender { get; set; }
        public AppUser Receiver { get; set; }
    }
}
