import pandas as pd
import os
import json
import sys 

input_dir = 'output/'
output_dir = sys.argv[1]
stim_path = sys.argv[2]

with open(stim_path) as f:
    stimuli = json.load(f)


def scale_and_merge_csvs():
    dfs = []
    for file_name in os.listdir(input_dir):
        if file_name.endswith('.csv'):
            file_path = os.path.join(input_dir, file_name)
            df = pd.read_csv(file_path)
            
            seq = file_name.split(".csv")[0]

            xs = stimuli["funcs"][seq]["true_coords"][0]
            ys = stimuli["funcs"][seq]["true_coords"][1]
            min_x = min(xs[:-1])
            max_x = max(xs[:-1])
            min_y = min(ys[:-1])
            max_y = max(ys[:-1])
            
            # Rescale input at tpt 0 (scaled bt 0 and 1)
            if min_x==max_x:
                df.loc[df['tpt'] == 0, 'true_x'] = df.loc[df['tpt'] == 0, 'true_x'] + min_x
            else:
                df.loc[df['tpt'] == 0, 'true_x'] = (df.loc[df['tpt'] == 0, 'true_x'] * (max_x-min_x)) + min_x
            if min_y==max_y:
                df.loc[df['tpt'] == 0, 'true_y'] = df.loc[df['tpt'] == 0, 'true_y'] + min_y
            else:
                df.loc[df['tpt'] == 0, 'true_y'] = (df.loc[df['tpt'] == 0, 'true_y'] * (max_y-min_y)) + min_y    
                
            # Rescale output and input, scaled between -1 and 1
            if min_x==max_x:
                df.loc[df['tpt'] != 0, 'true_x'] = df.loc[df['tpt'] != 0, 'true_x'] + min_x
                df["pred_x"] = df["pred_x"] + min_x
            else:
                df.loc[df['tpt'] != 0, 'true_x'] = (((df.loc[df['tpt'] != 0, 'true_x'] + 1)/2) * (max_x-min_x)) + min_x
                df["pred_x"] = (((df["pred_x"] + 1)/2) * (max_x-min_x)) + min_x
                df["sd_x"] = (df["sd_x"]/2)*(max_x-min_x)
            if min_y==max_y:
                df.loc[df['tpt'] != 0, 'true_y'] = df.loc[df['tpt'] != 0, 'true_y'] + min_y
                df["pred_y"] = df["pred_y"] + min_y
            else:
                df.loc[df['tpt'] != 0, 'true_y'] = (((df.loc[df['tpt'] != 0, 'true_y'] + 1)/2) * (max_y-min_y)) + min_y
                df["pred_y"] = (((df["pred_y"]+1)/2) * (max_y-min_y)) + min_y
                df["sd_y"] = (df["sd_y"]/2)*(max_y-min_y)
                
            dfs.append(df)
    
    merged_df = pd.concat(dfs, ignore_index=True)
    merged_df.to_csv(output_dir + '/gp.csv', index=False)


if __name__=="__main__":
    scale_and_merge_csvs()