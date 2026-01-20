#!/usr/bin/env python3

# View phone-level GOP scores with phone names
# Usage: view_gop_scores.py <gop_scp_file>

import sys
import re
import os

def main():
    if len(sys.argv) < 2:
        print("Usage: view_gop_scores.py <gop_scp_file>")
        sys.exit(1)
    
    gop_scp = sys.argv[1]
    
    # Find lang directory
    lang_dir = os.path.join(os.path.dirname(os.path.dirname(gop_scp)), "lang_nosp")
    
    # Load phone symbol table
    phone_map = {}
    phone_table = os.path.join(lang_dir, "phones-pure.txt")
    if not os.path.exists(phone_table):
        phone_table = os.path.join(lang_dir, "phones.txt")
    
    if os.path.exists(phone_table):
        with open(phone_table, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    phone_map[parts[1]] = parts[0]
    
    # Read GOP scp file to get ark path
    with open(gop_scp, 'r') as f:
        line = f.readline().strip()
        if not line:
            print("Error: Empty GOP scp file")
            sys.exit(1)
        parts = line.split()
        if len(parts) < 2:
            print("Error: Invalid GOP scp format")
            sys.exit(1)
        ark_path = parts[1].replace("ark:", "")
    
    # Read GOP scores using copy-post
    import subprocess
    cmd = f"copy-post ark:{ark_path} ark,t:- 2>/dev/null"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Error running copy-post: {result.stderr}")
        sys.exit(1)
    
    # Parse output
    for line in result.stdout.split('\n'):
        if not line.strip() or 'LOG' in line or 'Done' in line:
            continue
        
        # Parse: utterance_id [ phone_id gop ] [ phone_id gop ] ...
        parts = line.split()
        if len(parts) < 2:
            continue
        
        utt_id = parts[0]
        print(f"\n{'='*70}")
        print(f"Utterance: {utt_id}")
        print(f"{'='*70}")
        print(f"{'Phone ID':<12} {'Phone Name':<20} {'GOP Score':<15} {'Quality':<15}")
        print(f"{'-'*70}")
        
        # Extract [phone_id gop_score] pairs
        i = 1
        while i < len(parts):
            if parts[i].startswith('['):
                # Extract phone ID and GOP score
                phone_id = parts[i].strip('[')
                if i + 1 < len(parts):
                    gop_str = parts[i + 1].rstrip(']')
                    try:
                        phone_id_int = int(phone_id)
                        gop_score = float(gop_str)
                        
                        phone_name = phone_map.get(str(phone_id_int), "UNK")
                        
                        # Determine quality
                        if gop_score > 0:
                            quality = "Excellent"
                        elif gop_score > -1:
                            quality = "Good"
                        elif gop_score > -3:
                            quality = "Fair"
                        elif gop_score > -5:
                            quality = "Poor"
                        else:
                            quality = "Very Poor"
                        
                        print(f"{phone_id_int:<12} {phone_name:<20} {gop_score:<15.3f} {quality:<15}")
                        i += 2
                        continue
                    except ValueError:
                        pass
            i += 1
        
        print(f"{'='*70}\n")

if __name__ == "__main__":
    main()
