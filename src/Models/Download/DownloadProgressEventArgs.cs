using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Models.Download
{
    public class DownloadProgressEventArgs
    {
        public double ProgressPercentage { get; set; }
        public long DownloadedBytes { get; set; }
        public long TotalBytes { get; set; }
        public string Speed { get; set; }
        public string RemainingTime { get; set; }
        public string FileName { get; set; }
    }
}
