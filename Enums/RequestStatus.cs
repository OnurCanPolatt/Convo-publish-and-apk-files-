using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Enums
{
    public enum RequestStatus
    {
        Pending = 0,    // Bekliyor
        RemoveRequest=1,
        Accepted = 2,   // Kabul edildi
        Rejected = 3,    // Reddedildi
        RemoveFriend=4
    }
}
