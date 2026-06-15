using Microsoft.AspNetCore.Identity;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Entities
{
    public class AppRole : IdentityRole<Guid>
    {
        // Constructor - nesne yaratılınca çalışır
        public AppRole()
        {
            Id = Guid.NewGuid();
        }

        // İsimli constructor
        public AppRole(string roleName) : this()
        {
            Name = roleName;  // "Admin" VEYA "Member" VEYA "Moderator"
        }
    }
}
