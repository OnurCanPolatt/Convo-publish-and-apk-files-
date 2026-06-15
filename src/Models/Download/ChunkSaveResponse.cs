using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Domain.Models.Download
{
    public class ChunkSaveResponse
    {
        public bool Success { get; set; }
        public double ProgressPercentage { get; set; }
        public int CompletedChunks { get; set; }
        public int TotalChunks { get; set; }
    }
}
