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
        file_path = os.path.join(input_dir, file_name)
        df = pd.read_csv(file_path)
        seq = file_name.split(".csv")[0]
        xs = stimuli["funcs"][seq]["true_coords"][0]
        ys = stimuli["funcs"][seq]["true_coords"][1]
        scale_x = max(xs) - min(xs)
        if scale_x==0:
            df["true_x"] = (df["true_x"] + min(xs))
            df["pred_x"] = (df["pred_x"] + min(xs))
        else:
            df["pred_x"] = (df["pred_x"] - min(df["true_x"]))/(max(df["true_x"])- min(df["true_x"]))
            df["pred_x"] = (df["pred_x"]*scale_x) + min(xs)
            df["true_x"] = (df["true_x"] - min(df["true_x"]))/(max(df["true_x"])- min(df["true_x"]))
            df["true_x"] = (df["true_x"]*scale_x) + min(xs)
            df["sd_x"] = df["sd_x"]*scale_x
        scale_y = max(ys) - min(ys)
        if scale_y==0:
            df["true_y"] = (df["true_y"] + min(ys))
            df["pred_y"] = (df["pred_y"] + min(ys))
        else:
            df["pred_y"] = (df["pred_y"] - min(df["true_y"]))/(max(df["true_y"])- min(df["true_y"]))
            df["pred_y"] = (df["pred_y"]*scale_y) + min(ys)
            df["true_y"] = (df["true_y"] - min(df["true_y"]))/(max(df["true_y"])- min(df["true_y"]))
            df["true_y"] = (df["true_y"]*scale_y) + min(ys)
            df["sd_y"] = df["sd_y"]*scale_y
        dfs.append(df)
        
    merged_df = pd.concat(dfs, ignore_index=True)
    merged_df.to_csv(output_dir + '/polynomial.csv', index=False)

if __name__=="__main__":
    rescale_and_merge_csvs()