#!/usr/bin/env python3

# Aggregate phone-level GOP scores to utterance-level scores
# Usage: aggregate_utterance_scores.py <gop_scp> <output_file> [--method mean|median|min|weighted]

import sys
import argparse
import kaldi_io
import numpy as np

def get_args():
    parser = argparse.ArgumentParser(
        description='Aggregate phone-level GOP to utterance-level',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s exp/gop_test/gop.scp exp/utterance_scores.txt
  %(prog)s exp/gop_test/gop.scp exp/utterance_scores.txt --method weighted
        """)
    parser.add_argument('gop_scp', help='Input GOP scp file')
    parser.add_argument('output', help='Output utterance scores file')
    parser.add_argument('--method', choices=['mean', 'median', 'min', 'weighted'], 
                       default='mean', help='Aggregation method (default: mean)')
    parser.add_argument('--skip-silence', action='store_true', default=True,
                       help='Skip silence phones (0,1,2) in aggregation')
    return parser.parse_args()

def main():
    args = get_args()
    
    scores = {}
    
    try:
        for key, gops in kaldi_io.read_post_scp(args.gop_scp):
            # Extract GOP values
            gop_values = []
            for [(ph, gop)] in gops:
                # Skip silence phones if requested
                if args.skip_silence and ph in [0, 1, 2]:
                    continue
                gop_values.append(gop)
            
            if len(gop_values) == 0:
                print(f"Warning: No valid GOP values for {key}", file=sys.stderr)
                continue
            
            # Aggregate based on method
            if args.method == 'mean':
                score = np.mean(gop_values)
            elif args.method == 'median':
                score = np.median(gop_values)
            elif args.method == 'min':
                score = np.min(gop_values)  # Worst phone determines score
            elif args.method == 'weighted':
                # Weight by absolute GOP value (more weight to mispronunciations)
                weights = np.abs(gop_values)
                if np.sum(weights) > 0:
                    score = np.average(gop_values, weights=weights)
                else:
                    score = np.mean(gop_values)
            
            scores[key] = {
                'score': score,
                'num_phones': len(gop_values),
                'min_gop': np.min(gop_values),
                'max_gop': np.max(gop_values),
                'std_gop': np.std(gop_values)
            }
    except Exception as e:
        print(f"Error reading GOP file: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Write results
    try:
        with open(args.output, 'wt') as f:
            for key in sorted(scores.keys()):
                s = scores[key]
                f.write(f'{key}\t{s["score"]:.4f}\t{s["num_phones"]}\t'
                       f'{s["min_gop"]:.4f}\t{s["max_gop"]:.4f}\t{s["std_gop"]:.4f}\n')
        
        print(f"Wrote {len(scores)} utterance scores to {args.output}")
        if len(scores) > 0:
            avg_score = np.mean([s['score'] for s in scores.values()])
            print(f"Average utterance score: {avg_score:.4f}")
    except Exception as e:
        print(f"Error writing output: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
