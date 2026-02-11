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
            
            xs = stimuli["funcs"][seq]["true_coords"][0]
            ys = stimuli["funcs"][seq]["true_coords"][1]
            distances = [((xs[i+1] - xs[i])**2 + (ys[i+1] - ys[i])**2)**0.5 for i in range(len(xs)-1)]
            mean_dist = np.mean(distances)
            
            df = df[~((df["tpt"] > 1) & (df["sample"] != max(df["sample"])))]
            df = df.drop(columns=["sample", "pred_x", "pred_y"], errors="ignore")
            
            df["true_x"] = (df["true_x"] * mean_dist)
            df["true_y"] = (df["true_y"] * mean_dist)
            
            def f1(x):
                if isinstance(x, str):
                    x = eval(x)
                    return [mean_dist*i for i in x]
                return x
                    
            def f2(x):
                if isinstance(x, str):
                    x = eval(x)
                return x
            
            df['means_x'] = df['means_x'].apply(lambda x: f1(x))
            df['means_y'] = df['means_y'].apply(lambda x: f1(x))
            df['weights'] = df['weights'].apply(lambda x: f2(x))
            df["sd_x"] = df["sample_sd_x"] * mean_dist
            df["sd_y"] = df["sample_sd_y"] * mean_dist
            df["sd_periodic_x"] = df["sd_periodic_x"] * mean_dist
            df["sd_periodic_y"] = df["sd_periodic_y"] * mean_dist
            df["sd_vec_x"] = df["sd_vec_x"] * mean_dist
            df["sd_vec_y"] = df["sd_vec_y"] * mean_dist
            df['is_periodic'] = df['weights'].apply(lambda w: [1] * (len(w) - 1) + [0] if isinstance(w, list) else np.nan)

            df = df.explode(['means_x', 'weights', 'means_y', 'is_periodic'])
            
            df = (df
             .drop(columns=[
                "sample_sd_x", "sample_sd_y", "args", "choices",
                "sd_x", "sd_y"
             ])

             .rename(columns={
                "weights": "component_weight",
                "means_x": "mean_x",
                "means_y": "mean_y"
             })
            )
            
            dfs.append(df)
                
    merged_df = pd.concat(dfs, ignore_index=True)
    merged_df.to_csv(output_dir + '/linear_or_prev.csv', index=False)


if __name__=="__main__":   
    rescale_and_merge_csvs()