import pandas as pd
import os
import json
import numpy as np

with open('../stimuli.json') as f:
    stim = json.load(f)

outdir = 'output/'

def rescale_and_merge_csvs(path):
    dfs = []
    for file_name in os.listdir(path):
        if file_name.endswith('.csv') and not(file_name.endswith('scores.csv')):
            file_path = os.path.join(path, file_name)
            df = pd.read_csv(file_path)
            seq = file_name.split(".csv")[0]
            # rescale predictions
            xs = stim["funcs"][seq]["true_coords"][0]
            ys = stim["funcs"][seq]["true_coords"][1]
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
    merged_df.to_csv(path + 'linear.csv', index=False)


rescale_and_merge_csvs(outdir)