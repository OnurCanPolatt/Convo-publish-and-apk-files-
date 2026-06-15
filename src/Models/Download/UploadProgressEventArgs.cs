using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Models.Download
{
    public class UploadProgressEventArgs
    {
        public double ProgressPercentage { get; set; }
        public long UploadedBytes { get; set; }
        public long TotalBytes { get; set; }
        public string Speed { get; set; }
        public string RemainingTime { get; set; }
        public int CompletedChunks { get; set; }
        public int TotalChunks { get; set; }
    }
}
