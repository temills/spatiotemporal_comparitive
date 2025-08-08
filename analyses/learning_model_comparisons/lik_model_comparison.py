import pandas as pd
import numpy as np
import sys
from scipy.stats import norm, uniform
from scipy.optimize import minimize
import json
import os
import psutil

sm = 1e-10 



def compute_p_data(df): 
    df['lik_x'] = norm.pdf(df['pred_x'], loc=df['model_pred_x'],
                           #scale=np.sqrt(df['sd_motor']**2))
                            scale=np.sqrt(df['model_std_x']**2 + df['sd_motor']**2))
    df['lik_y'] = norm.pdf(df['pred_y'], loc=df['model_pred_y'], 
                           #scale=np.sqrt(df['sd_motor']**2))
                            scale=np.sqrt(df['model_std_y']**2 + df['sd_motor']**2))
    
    # Within group, sum across particles and take arbitrary particle
    # df.groupby(['subj_id', 'func.name', 'n', 'r_id'])...
    df['weighted_lik_x'] = df['model_posterior'] * df['lik_x']
    df['weighted_lik_y'] = df['model_posterior'] * df['lik_y']
    sum_x = df.groupby(['subj_id', 'func.name', 'n', 'r_id'])['weighted_lik_x'].transform('sum')
    sum_y = df.groupby(['subj_id', 'func.name', 'n', 'r_id'])['weighted_lik_y'].transform('sum')
    df['p_data_x'] = sm + (1 - sm) * sum_x
    df['p_data_y'] = sm + (1 - sm) * sum_y
    df_summ = df.sort_values('model_particle', ascending=False).groupby(['subj_id', 'func.name', 'n', 'r_id'], sort=False).head(1)
    
    df_summ['p_data_x'] = ((1 - df_summ['p_lapse']) * df_summ['p_data_x'] +
                            df_summ['p_prev'] * norm.pdf(df_summ['pred_x'], 
                                                    loc=df_summ['prev_x'], 
                                                    scale=df_summ['sd_prev']) +
                            df_summ['p_lin'] * norm.pdf(df_summ['pred_x'], 
                                                    loc=df_summ['pred_x_lin'], 
                                                    scale=df_summ['sd_lin']) +
                            df_summ['p_rand'] * uniform.pdf(df_summ['pred_x'], 
                                                       loc=df_summ['min_x'], 
                                                       scale=df_summ['max_x'] - df_summ['min_x']))
        
    df_summ['p_data_y'] = ((1 - df_summ['p_lapse']) * df_summ['p_data_y'] +
                            df_summ['p_prev'] * norm.pdf(df_summ['pred_y'], 
                                                    loc=df_summ['prev_y'], 
                                                    scale=df_summ['sd_prev']) +
                            df_summ['p_lin'] * norm.pdf(df_summ['pred_y'], 
                                                    loc=df_summ['pred_y_lin'], 
                                                    scale=df_summ['sd_lin']) +
                            df_summ['p_rand'] * uniform.pdf(df_summ['pred_y'], 
                                                        loc=df_summ['min_y'], 
                                                        scale=df_summ['max_y'] - df_summ['min_y']))
    
    return df_summ

# Should prob do this without group apply
def compute_p_data2(df): 
    def group_apply(group):
        group['p_data_x'] = norm.pdf(group['pred_x'], loc=group['model_pred_x'], 
                                        scale=np.sqrt(group['model_std_x']**2 + group['sd_motor']**2))
        group['p_data_x'] = sm + (1 - sm) * np.sum(group['model_posterior'] * group['p_data_x'])
        
        group['p_data_y'] = norm.pdf(group['pred_y'], loc=group['model_pred_y'], 
                                        scale=np.sqrt(group['model_std_y']**2 + group['sd_motor']**2))
        group['p_data_y'] = sm + (1 - sm) * np.sum(group['model_posterior'] * group['p_data_y'])
        
        group = group.nlargest(1, 'model_particle')
        group['p_data_x'] = ((1 - group['p_lapse']) * group['p_data_x'] +
                                group['p_prev'] * norm.pdf(group['pred_x'], 
                                                        loc=group['prev_x'], 
                                                        scale=group['sd_prev']) +
                                group['p_lin'] * norm.pdf(group['pred_x'], 
                                                        loc=group['pred_x_lin'], 
                                                        scale=group['sd_lin']) +
                                group['p_rand'] * uniform.pdf(group['pred_x'], 
                                                            loc=group['min_x'], 
                                                            scale=group['max_x'] - group['min_x']))
        
        group['p_data_y'] = ((1 - group['p_lapse']) * group['p_data_y'] +
                                group['p_prev'] * norm.pdf(group['pred_y'], 
                                                        loc=group['prev_y'], 
                                                        scale=group['sd_prev']) +
                                group['p_lin'] * norm.pdf(group['pred_y'], 
                                                        loc=group['pred_y_lin'], 
                                                        scale=group['sd_lin']) +
                                group['p_rand'] * uniform.pdf(group['pred_y'], 
                                                            loc=group['min_y'], 
                                                            scale=group['max_y'] - group['min_y']))
        return group
    
    return df.groupby(['subj_id', 'func.name', 'n', 'r_id'])[df.columns].apply(group_apply) 


def compute_ll(df_participant_model, fit_rand=False, fit_lin=False):
    # Function to minimize
    def fn(pars):
        if not fit_rand:
            pars = np.append(pars, 0)
        if not fit_lin:
            pars = np.append(pars, 0)
            pars = np.append(pars, 0.1)
        
        df_result = df_optim
        df_result['p_lapse'], df_result['sd_motor'], df_result['sd_prev'], df_result['p_rand0'], df_result['p_lin0'], df_result['sd_lin'] = pars
        df_result['p_rand'] = df_result['p_lapse'] * df_result['p_rand0']
        df_result['p_prev'] = df_result['p_lapse'] * (1 - df_result['p_rand0']) * (1-df_result['p_lin0'])
        df_result['p_lin'] = df_result['p_lapse'] * (1 - df_result['p_rand0']) * (df_result['p_lin0'])
        
        df_result = compute_p_data(df_result)
        
        if np.any(df_result['p_data_x'] <= 0) or np.any(df_result['p_data_y'] <= 0):
            print("Warning: Zero or negative values in p_data_x or p_data_y!")
            print(df_result[df_result['p_data_x'] <= 0])
            print(df_result[df_result['p_data_y'] <= 0])
            
        df_result['LL'] = np.log(df_result['p_data_x']) + np.log(df_result['p_data_y'])
        return -np.nansum(df_result['LL'])


    # Iterate thru subjects, minimize fn
    subj_param_dict = {}
    for subj in df_participant_model['subj_id'].unique():
        init_pars = [0.2, 0.08, 0.08]
        bounds = [(0, 0.99), (1e-5, 1), (1e-5, 1)]
        
        if fit_rand:
            init_pars.append(0.1)
            bounds.append((0, 1))
        if fit_lin:
            assert(fit_rand)
            init_pars.append(0.5)
            bounds.append((0, 1))
            init_pars.append(0.08)
            bounds.append((1e-5, 1))
        
        global df_optim
        df_optim = df_participant_model[df_participant_model['subj_id'] == subj].copy()
        df_optim = df_optim[df_optim['n'] > 2]
        
        res = minimize(fn, init_pars, bounds=bounds, options={'disp': False})
        if not res.success:
            print(f"Optimization failed for subject {subj}: {res.message}")
        
        pars = res.x
        if not fit_rand:
            assert(not fit_lin)
            pars = np.append(pars, 0)
        if not fit_lin:
            pars = np.append(pars, 0)
            pars = np.append(pars, 0.1)
             
        subj_param_dict[subj] = pars

    # Store results
    def apply_params(row):
        pars = subj_param_dict[row['subj_id']]
        return pd.Series({'p_lapse': pars[0], 'sd_motor': pars[1], 'sd_prev': pars[2], 'p_rand0': pars[3], 'p_lin0': pars[4], 'sd_lin': pars[5]})
    
    df_result = df_participant_model.copy()
    df_result = df_result.join(df_result.apply(apply_params, axis=1))
    df_result['p_rand'] = df_result['p_lapse'] * df_result['p_rand0']
    df_result['p_prev'] = df_result['p_lapse'] * (1 - df_result['p_rand0']) * (1 - df_result['p_lin0'])
    df_result['p_lin'] = df_result['p_lapse'] * (1 - df_result['p_rand0']) * df_result['p_lin0']
    df_result = df_result[df_result['n'] > 2]
    df_result = compute_p_data(df_result)
    df_result['LL'] = np.log(df_result['p_data_x']) + np.log(df_result['p_data_y'])

    print(np.nansum(df_result['LL']))
    return df_result



def compute_ll_baseline(df_participant_model, fit_rand=False, fit_lin=False):
    # Function to minimize
    def fn(pars):
        df_result = df_optim.copy()
        df_result['sd_prev'], df_result['p_rand'] = pars
        df_result['p_prev'] = (1 - df_result['p_rand'])
        df_result['p_lapse'] = 0
        df_result['p_lin'] = 0
        df_result['sd_motor'] = 1
        df_result['sd_lin'] = 1
        df_result = df_result[df_result['n'] > 2]
        df_result = compute_p_data(df_result)
        
        if np.any(df_result['p_data_x'] <= 0) or np.any(df_result['p_data_y'] <= 0):
            print("Warning: Zero or negative values in p_data_x or p_data_y!")
            print(df_result[df_result['p_data_x'] <= 0])
            print(df_result[df_result['p_data_y'] <= 0])
            
        df_result['LL'] = np.log(df_result['p_data_x']) + np.log(df_result['p_data_y'])
        return -np.nansum(df_result['LL'])


    # Iterate thru subjects, minimize fn
    subj_param_dict = {}
    for subj in df_participant_model['subj_id'].unique():
        init_pars = [0.08, 0.1]
        bounds = [(1e-5, 1), (0, 1)]
        
        global df_optim
        df_optim = df_participant_model[df_participant_model['subj_id'] == subj].copy()
        df_optim["model_std_x"] = 0
        df_optim["model_std_y"] = 0
        
        res = minimize(fn, init_pars, bounds=bounds, options={'disp': False})
        if not res.success:
            print(f"Optimization failed for subject {subj}: {res.message}")
        
        pars = res.x
             
        subj_param_dict[subj] = pars

    # Store results
    def apply_params(row):
        pars = subj_param_dict[row['subj_id']]
        return pd.Series({'sd_prev': pars[0], 'p_rand': pars[1]})
    
    df_result = df_participant_model.copy()
    df_result = df_result.join(df_result.apply(apply_params, axis=1))
    df_result['p_rand'] = df_result['p_rand']
    df_result['p_prev'] = (1 - df_result['p_rand'])
    df_result['p_lapse'] = 0
    df_result['p_lin'] = 0
    df_result['sd_motor'] = 1
    df_result['sd_lin'] = 1
    df_result = df_result[df_result['n'] > 2]
    df_result = compute_p_data(df_result)
    df_result['LL'] = np.log(df_result['p_data_x']) + np.log(df_result['p_data_y'])

    print(np.nansum(df_result['LL']))
    return df_result


def compute_ll_single_subj(df_subj, fit_rand=False, fit_lin=False):
    # Function to minimize
    def fn(pars):
        if not fit_rand:
            pars = np.append(pars, 0)
        if not fit_lin:
            pars = np.append(pars, 0)
            pars = np.append(pars, 0.1)
        
        df_subj.loc[:, 'p_lapse'] = pars[0]
        df_subj.loc[:, 'sd_motor'] = pars[1]
        df_subj.loc[:, 'sd_prev'] = pars[2]
        df_subj.loc[:, 'p_rand0'] = pars[3]
        df_subj.loc[:, 'p_lin0'] = pars[4]
        df_subj.loc[:, 'sd_lin'] = pars[5]

        df_subj.loc[:, 'p_rand'] = df_subj['p_lapse'] * df_subj['p_rand0']
        df_subj.loc[:, 'p_prev'] = df_subj['p_lapse'] * (1 - df_subj['p_rand0']) * (1 - df_subj['p_lin0'])
        df_subj.loc[:, 'p_lin'] = df_subj['p_lapse'] * (1 - df_subj['p_rand0']) * df_subj['p_lin0']

        df_res = compute_p_data(df_subj)
        
        if np.any(df_res['p_data_x'] <= 0) or np.any(df_res['p_data_y'] <= 0):
            print("Warning: Zero or negative values in p_data_x or p_data_y!")
            print(df_res[df_res['p_data_x'] <= 0])
            print(df_res[df_res['p_data_y'] <= 0])
            
        df_res['LL'] = np.log(df_res['p_data_x']) + np.log(df_res['p_data_y'])
        return -np.nansum(df_res['LL'])

    # minimize fn
    init_pars = [0.2, 0.08, 0.08]
    bounds = [(0, 0.99), (1e-5, 1), (1e-5, 1)]
    
    if fit_rand:
        init_pars.append(0.1)
        bounds.append((0, 1))
    if fit_lin:
        assert(fit_rand)
        init_pars.append(0.5)
        bounds.append((0, 1))
        init_pars.append(0.08)
        bounds.append((1e-5, 1))
    
    res = minimize(fn, init_pars, bounds=bounds, options={'disp': False})
    if not res.success:
        print(f"Optimization failed for subject: {res.message}")
    
    pars = res.x
    if not fit_rand:
        assert(not fit_lin)
        pars = np.append(pars, 0)
    if not fit_lin:
        pars = np.append(pars, 0)
        pars = np.append(pars, 0.1)
            
    df_subj['p_lapse'], df_subj['sd_motor'], df_subj['sd_prev'], df_subj['p_rand0'], df_subj['p_lin0'], df_subj['sd_lin']  = pars[0], pars[1], pars[2], pars[3], pars[4], pars[5]
    df_subj['p_rand'] = df_subj['p_lapse'] * df_subj['p_rand0']
    df_subj['p_prev'] = df_subj['p_lapse'] * (1 - df_subj['p_rand0']) * (1 - df_subj['p_lin0'])
    df_subj['p_lin'] = df_subj['p_lapse'] * (1 - df_subj['p_rand0']) * df_subj['p_lin0']
    df_subj = compute_p_data(df_subj)
    df_subj['LL'] = np.log(df_subj['p_data_x']) + np.log(df_subj['p_data_y'])
    LL = np.nansum(df_subj['LL'])
    
    return {'p_lapse': pars[0], 'sd_motor': pars[1], 'sd_prev':pars[2], 'p_rand': pars[0]*pars[3], 'p_prev': pars[0]*(1-pars[3]), 'LL':LL}
    


def create_loo_crossval_stimuli():
    stimuli = []
    for participant_name in ["kid_chs", "adult", "monkey"]:
        for model_name in ["lin_prev", "lot", "gpnc", "gpsl", "ridge", "lin"]:
            df_participant_model = pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "string"}) 
            for subj in df_participant_model['subj_id'].unique():
                df_subj = df_participant_model[df_participant_model["subj_id"]==subj].copy()
                for func_name in df_subj['func.name'].unique():
                    stimuli.append((participant_name, model_name, subj, func_name))
    with open('crossval_data/stimuli.json', 'w') as f:
        json.dump(stimuli, f)

def run_loo_crossval(stimulus_idx):
    """
    We need to fit params for each subj/func/model combo
    Let's store these somewhere and then we can load them
    We will store the params and the LL
    CSV with: subj_id, func.name, model, phase (train or test), LL, motor_sd, prev_sd, p_lapse, p_rand
    """
    with open('crossval_data/stimuli.json') as f:
        stimuli = json.load(f)
        
    #print(len([x for x in stimuli if x[0]=="kid_chs"]))
    #print(len(stimuli))
    print(stimuli[stimulus_idx])
    participant_name, model_name, subj, func_name = stimuli[stimulus_idx]
    df_participant_model = pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "string"})
    df_subj = df_participant_model[df_participant_model["subj_id"]==subj]
    df_subj = df_subj[df_subj['n'] > 2]
    df_subj_train = df_subj[df_subj['func.name'] != func_name].copy()
    df_subj_test = df_subj[df_subj['func.name'] == func_name].copy()
    d_train = compute_ll_single_subj(df_subj_train, True, False)
    d_train["phase"], d_train["subj"], d_train["func.name"] = "train", subj, func_name
    d_test = compute_ll_single_subj(df_subj_test, True, False)
    d_test["phase"], d_test["subj"], d_test["func.name"] = "test", subj, func_name
    # store [d_train, d_test]
    fname = "crossval_data/" + participant_name + "/" + model_name + "_" + subj + "_" + func_name + ".json"
    with open(fname, 'w') as f:
        json.dump([d_train, d_test], f)


def loo_crossval_results():
    # for each json file in crossval_data/kid_chs:
    dir = "crossval_data/kid_chs/"
    for name in os.listdir(dir):
        fname = os.path.join(dir, name)
        with open(fname) as f:
            dicts = json.load(f)
        dict_list = dict_list + dicts
    df = pd.DataFrame(dict_list)
    df.to_csv('crossval_data/output.csv', index=False)

def run_all():
    pairs = []
    for participant_name in ["kid_chs"]: #,"monkey",  "adult"]
        for model_name in ["lot", "gpnc", "gpsl", "ridge", "lin", "lin_prev", "transformer_1", "transformer_4", "transformer_5", "transformer_6", "transformer_8", "transformer_10", "transformer_2", "transformer_3", "transformer_13", "lot_no_recursion"]:
            pairs.append((participant_name, model_name))
    i=0
    for (participant_name, model_name) in pairs:
        print(participant_name)
        print(model_name)
        df_participant_model = pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "string"})
        out_path = "model_fits/" + model_name + "_" + participant_name + ".csv"
        df_res = compute_ll(df_participant_model, True, False)
        df_res.to_csv(out_path, index=False)
        # now baseline
        # if i==0:
        #      df_participant_model = pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv")
        #      model_name = "baseline"
        #      out_path = "model_fits/" + model_name + "_" + participant_name + ".csv"
        #      df_res = compute_ll_baseline(df_participant_model, True, False)
        #      df_res.to_csv(out_path, index=False)
        #      i = 1 


def run_bootstrapping(seed):
    # resample functions once
    # we'll eventually take mean across participants within functions 
    # and then mean of function means
    # recompute this many times to get distribution of means
    np.random.seed(seed)
    for participant_name in ["kid_chs", "adult", "monkey"]:
        df_tmp = pd.read_csv("preprocessed_data/lot_" + participant_name + ".csv", dtype={"func.name": "string"})
        unique_funcs = df_tmp['func.name'].unique()
        boot_funcs = np.random.choice(unique_funcs, size=len(unique_funcs), replace=True)
        
        for model_name in ["lin_prev", "transformer_2", "transformer_3", "transformer_13", "lot", "lot_no_recursion", "gpnc", "gpsl", "ridge", "lin"]:
            print(participant_name, model_name) 
            chunks = []
            for chunk in pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "category", "r_id":"category", "subj_id":"category"}, chunksize=100_000):
                chunks.append(chunk)
            df_participant_model = pd.concat(chunks, ignore_index=True)

            boot_df_list = []
            for i, func in enumerate(boot_funcs):
                subset = df_participant_model[df_participant_model['func.name'] == func].copy()
                subset['original_func.name'] = func
                subset['func.name'] = "f" + str(i) 
                boot_df_list.append(subset)
            # concat resampled data
            boot_df = pd.concat(boot_df_list, ignore_index=True)
            
            # do this separately by subj?
            out_path = "model_fits/bootstrapping/" + model_name + "_" + participant_name + "_" + str(seed) + ".csv"
            
            df_res = compute_ll(boot_df, True, False)
            df_res.to_csv(out_path, index=False)


def run_bootstrapping():
    # resample functions once
    # we'll eventually take mean across participants within functions 
    # and then mean of function means
    # recompute this many times to get distribution of means
    for participant_name in ["kid_chs", "adult", "monkey"]:
        df_tmp = pd.read_csv("preprocessed_data/lot_" + participant_name + ".csv", dtype={"func.name": "string"})
        unique_funcs = df_tmp['func.name'].unique()
        
        for seed in range(100):
            np.random.seed(seed)
            boot_funcs = np.random.choice(unique_funcs, size=len(unique_funcs), replace=True)
            
            for model_name in ["lin_prev", "transformer_2", "transformer_3", "transformer_13", "lot", "lot_no_recursion", "gpnc", "gpsl", "ridge", "lin"]:
                print(participant_name, model_name) 
                #chunks = []
                #for chunk in pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "category", "r_id":"category", "subj_id":"category"}, chunksize=100_000, low_memory=False):
                #    chunks.append(chunk)
                #df_participant_model = pd.concat(chunks, ignore_index=True)
                df_participant_model = pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "string"})#, "r_id":"category", "subj_id":"category"})
                boot_df_list = []
                for i, func in enumerate(boot_funcs):
                    subset = df_participant_model[df_participant_model['func.name'] == func].copy()
                    subset['original_func.name'] = func
                    subset['func.name'] = "f" + str(i) 
                    boot_df_list.append(subset)

                # concat resampled data
                boot_df = pd.concat(boot_df_list, ignore_index=True)
                out_path = "model_fits/bootstrapping/" + model_name + "_" + participant_name + "_" + str(seed) + ".csv"
                df_res = compute_ll(boot_df, True, False)
                df_res.to_csv(out_path, index=False)


# run lik analysis on monkey train data
def run_monkey_train():
    pairs = []
    for participant_name in ["monkey"]:
        for model_name in ["transformer_" + str(i) for i in [1,2,3,4,5,6,8,10,13]]:#range(1,14)]:
            pairs.append((participant_name, model_name))
    for (participant_name, model_name) in pairs:
        print(participant_name)
        print(model_name)
        df_participant_model = pd.read_csv("preprocessed_data/monkey_training/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "string"})
        out_path = "model_fits/monkey_training_no_model_std/" + model_name + "_" + participant_name + ".csv"
        df_res = compute_ll(df_participant_model, True, False)
        df_res.to_csv(out_path, index=False)

if __name__=="__main__":
    run_all()
    #run_monkey_train()
    #run_monkey_train()
    #run_bootstrapping()
    # sample = pd.read_csv("preprocessed_data/lin_prev_kid_chs.csv", dtype={"func.name": "category", "r_id":"category", "subj_id":"category"}, nrows=500)
    # print(sample.dtypes)

    # ksmj
    # process = psutil.Process(os.getpid())

    # # Memory before loading
    # mem_before = process.memory_info().rss / 1024**3

    # df = pd.read_csv("preprocessed_data/lin_prev_kid_chs.csv")

    # # Memory after loading
    # mem_after = process.memory_info().rss / 1024**3

    # print(f"DataFrame memory (df.memory_usage): {df.memory_usage(deep=True).sum() / 1024**3:.2f} GB")
    # print(f"Memory used by process: {mem_after - mem_before:.2f} GB (approx)")

    #run_all()
    
    #create_loo_crossval_stimuli()
    #for i in range(2098, 2099):
    #    run_loo_crossval(i)
    #    print(i)
    
#2098 lin_prev
#12964
#15736

