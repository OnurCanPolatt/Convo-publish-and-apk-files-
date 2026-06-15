using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Convo.Shared.Models.Dtos
{
    public class ApiErrorResponse
    {
        public string Error { get; set; } = "";
        public string Message { get; set; } = "";
    }
}
