using Domain.Entities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Models.Download
{
    public class FileUploadResult
    {
        public bool Success { get; set; }
        public Message Message { get; set; }
        public string DownloadUrl { get; set; }
        public string ErrorMessage { get; set; }
    }
}
