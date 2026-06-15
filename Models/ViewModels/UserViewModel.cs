using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Convo.Shared.Models.ViewModels
{
    public class UserViewModel
    {
        public string? ProfileImageUrl { get; set; }
        public string userName { get; set; }
        public string About{ get; set; }
        public string Phone { get; set; }
        public string Email{ get; set; }


    }
}
