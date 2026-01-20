#!/usr/bin/env python3
# Aggregate phone-level ML scores to utterance-level scores
# Input: phone_scores_ml.txt (from feat_to_score_eval.py)
# Format: phone_key score phone_id

import sys
import argparse
import numpy as np

def get_args():
    parser = argparse.ArgumentParser(
        description='Aggregate phone-level ML scores to utterance-level',
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('phone_scores_file', help='Input phone scores file from feat_to_score_eval.py')
    parser.add_argument('output_file', help='Output utterance score file')
    parser.add_argument('--method', type=str, default='mean', 
                       choices=['mean', 'median', 'min', 'max'],
                       help='Aggregation method (default: mean)')
    return parser.parse_args()

def main():
    args = get_args()
    
    # Group scores by utterance
    utterance_scores = {}
    
    with open(args.phone_scores_file, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) < 2:
                continue
            
            phone_key = parts[0]  # Format: utterance_id.phone_index
            score = float(parts[1])
            
            # Extract utterance ID (before the last dot)
            utt_id = '.'.join(phone_key.split('.')[:-1])
            
            if utt_id not in utterance_scores:
                utterance_scores[utt_id] = []
            utterance_scores[utt_id].append(score)
    
    # Aggregate scores
    with open(args.output_file, 'w') as f:
        for utt_id in sorted(utterance_scores.keys()):
            scores = utterance_scores[utt_id]
            
            if args.method == 'mean':
                agg_score = np.mean(scores)
            elif args.method == 'median':
                agg_score = np.median(scores)
            elif args.method == 'min':
                agg_score = np.min(scores)
            elif args.method == 'max':
                agg_score = np.max(scores)
            
            num_phones = len(scores)
            min_score = np.min(scores)
            max_score = np.max(scores)
            std_score = np.std(scores)
            
            f.write(f'{utt_id}\t{agg_score:.4f}\t{num_phones}\t{min_score:.4f}\t{max_score:.4f}\t{std_score:.4f}\n')

if __name__ == "__main__":
    main()
