import pandas as pd
import os
import json
import numpy as np
import sys 

input_dir = 'output/'
output_dir = sys.argv[1]
stim_path = sys.argv[2]

with open(stim_path) as f:
    stimuli = json.load(f)

def rescale_and_merge_csvs():
    dfs = []
    for file_name in os.listdir(input_dir):
        if file_name.endswith('.csv') and not(file_name.endswith('scores.csv')):
            file_path = os.path.join(input_dir, file_name)
            df = pd.read_csv(file_path)
            seq = file_name.split(".csv")[0]
            # rescale predictions
            xs = stimuli["funcs"][seq]["true_coords"][0]
            ys = stimuli["funcs"][seq]["true_coords"][1]
            distances = [((xs[i+1] - xs[i])**2 + (ys[i+1] - ys[i])**2)**0.5 for i in range(len(xs)-1)]
            mean_dist = np.mean(distances)
            df["true_x"] = (df["true_x"] * mean_dist)
            df["pred_x"] = (df["pred_x"] * mean_dist)
            df["true_y"] = (df["true_y"] * mean_dist)
            df["pred_y"] = (df["pred_y"] * mean_dist)
            df["sd_x"] = df["sd_x"] * mean_dist
            df["sd_y"] = df["sd_y"] * mean_dist
            df["sampled_sd_x"] = df["sd_x"] * mean_dist
            df["sampled_sd_y"] = df["sd_y"] * mean_dist

            dfs.append(df)
    merged_df = pd.concat(dfs, ignore_index=True)
    merged_df.to_csv(output_dir + '/linear.csv', index=False)

if __name__=="__main__":
    rescale_and_merge_csvs()