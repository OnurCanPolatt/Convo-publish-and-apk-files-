using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace Domain.Enums
{
    public interface IFileData
    {
        string FileName { get; set; }
        string ContentType { get; set; }
        long FileSize { get; set; }
        DateTime UploadedAt { get; set; }
        MessageType FileType { get; set; }
    }
}
