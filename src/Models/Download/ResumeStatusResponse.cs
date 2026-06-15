using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Models.Download
{
    public class ResumeStatusResponse
    {
        public List<int> CompletedChunkIndexes { get; set; }
        public int TotalChunks { get; set; }
        public double ProgressPercentage { get; set; }
    }
}
