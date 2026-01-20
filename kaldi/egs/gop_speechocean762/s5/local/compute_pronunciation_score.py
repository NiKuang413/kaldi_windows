#!/usr/bin/env python3

# Compute pronunciation score from GOP values, normalized to 0-100 scale
# Usage: compute_pronunciation_score.py <utterance_score_file> [--baseline <native_baseline>]

import sys
import argparse
import numpy as np

def get_args():
    parser = argparse.ArgumentParser(
        description='Compute pronunciation score (0-100) from GOP utterance scores',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
This script converts raw GOP scores to a 0-100 pronunciation quality scale.
Higher scores indicate better pronunciation (closer to native speakers).

Scoring method:
  - GOP > 0: Excellent (90-100)
  - GOP = 0: Good (70-90)
  - GOP < 0: Needs improvement (0-70)

If --baseline is provided, scores are normalized against native speaker baseline.
        """)
    parser.add_argument('utterance_score_file', help='Input utterance scores file (from aggregate_utterance_scores.py)')
    parser.add_argument('--output', help='Output file (default: stdout)')
    parser.add_argument('--baseline', type=float, help='Native speaker baseline GOP score (for normalization)')
    parser.add_argument('--min-score', type=float, default=0.0, help='Minimum score (default: 0)')
    parser.add_argument('--max-score', type=float, default=100.0, help='Maximum score (default: 100)')
    return parser.parse_args()

def gop_to_score(gop_value, baseline=None, min_score=0, max_score=100):
    """
    Convert GOP score to 0-100 pronunciation quality score.
    
    GOP interpretation:
    - GOP > 0: Canonical phone has highest probability (excellent)
    - GOP = 0: Canonical phone tied with best (good)
    - GOP < 0: Another phone has higher probability (needs improvement)
    """
    if baseline is not None:
        # Normalize against baseline
        # If user's GOP is close to baseline, score is high
        diff = gop_value - baseline
        # Map difference to score: diff=0 -> 100, diff=-5 -> 50, diff<-10 -> 0
        if diff >= 0:
            score = max_score
        elif diff >= -2:
            score = max_score + (diff / 2) * 10  # 100 to 90
        elif diff >= -5:
            score = 90 + ((diff + 2) / 3) * 40  # 90 to 50
        else:
            score = max(50 + ((diff + 5) / 5) * 50, min_score)  # 50 to 0
    else:
        # Direct mapping without baseline
        if gop_value >= 0:
            score = 90 + min(gop_value * 2, 10)  # 90-100
        elif gop_value >= -1:
            score = 80 + (gop_value + 1) * 10  # 80-90
        elif gop_value >= -3:
            score = 60 + ((gop_value + 1) / 2) * 20  # 60-80
        elif gop_value >= -5:
            score = 40 + ((gop_value + 3) / 2) * 20  # 40-60
        else:
            score = max(40 + ((gop_value + 5) / 5) * 40, min_score)  # 0-40
    
    return max(min(score, max_score), min_score)

def main():
    args = get_args()
    
    results = []
    
    try:
        with open(args.utterance_score_file, 'rt') as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) < 2:
                    continue
                
                utt_id = parts[0]
                gop_score = float(parts[1])
                num_phones = int(parts[2]) if len(parts) > 2 else 0
                
                # Convert to pronunciation score
                pronunciation_score = gop_to_score(
                    gop_score, 
                    args.baseline, 
                    args.min_score, 
                    args.max_score
                )
                
                results.append({
                    'utt_id': utt_id,
                    'gop_score': gop_score,
                    'pronunciation_score': pronunciation_score,
                    'num_phones': num_phones
                })
    except Exception as e:
        print(f"Error reading input file: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Write output
    output_file = sys.stdout if args.output is None else open(args.output, 'wt')
    
    try:
        # Header
        output_file.write("Utterance_ID\tGOP_Score\tPronunciation_Score\tNum_Phones\tGrade\n")
        
        for r in results:
            # Determine grade
            score = r['pronunciation_score']
            if score >= 90:
                grade = "Excellent"
            elif score >= 80:
                grade = "Good"
            elif score >= 70:
                grade = "Fair"
            elif score >= 60:
                grade = "Needs Improvement"
            else:
                grade = "Poor"
            
            output_file.write(f"{r['utt_id']}\t{r['gop_score']:.4f}\t"
                           f"{r['pronunciation_score']:.2f}\t{r['num_phones']}\t{grade}\n")
        
        if len(results) > 0:
            avg_gop = np.mean([r['gop_score'] for r in results])
            avg_pron = np.mean([r['pronunciation_score'] for r in results])
            output_file.write(f"\n# Average GOP: {avg_gop:.4f}\n")
            output_file.write(f"# Average Pronunciation Score: {avg_pron:.2f}/100\n")
            
            if args.output is None:
                print(f"\n# Average GOP: {avg_gop:.4f}", file=sys.stderr)
                print(f"# Average Pronunciation Score: {avg_pron:.2f}/100", file=sys.stderr)
        
        if args.output is not None:
            output_file.close()
            print(f"Results written to {args.output}")
    
    except Exception as e:
        print(f"Error writing output: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
