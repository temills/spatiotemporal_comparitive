import pandas as pd
import numpy as np
from scipy.stats import norm, uniform
from scipy.optimize import minimize




sm = 1e-10 

def compute_p_data(df): 
    df['lik_x'] = norm.pdf(df['pred_x'], loc=df['model_pred_x'],
                            scale=np.sqrt(df['model_std_x']**2 + df['sd_motor']**2))
    df['lik_y'] = norm.pdf(df['pred_y'], loc=df['model_pred_y'], 
                            scale=np.sqrt(df['model_std_y']**2 + df['sd_motor']**2))
    
    # Within group, sum across particles and take arbitrary particle
    df['weighted_lik_x'] = df['model_posterior'] * df['lik_x']
    df['weighted_lik_y'] = df['model_posterior'] * df['lik_y']
    sum_x = df.groupby(['subj_id', 'func.name', 'tpt', 'r_id'])['weighted_lik_x'].transform('sum')
    sum_y = df.groupby(['subj_id', 'func.name', 'tpt', 'r_id'])['weighted_lik_y'].transform('sum')
    df['p_data_x'] = sm + (1 - sm) * sum_x
    df['p_data_y'] = sm + (1 - sm) * sum_y
    df_summ = df.sort_values('model_particle', ascending=False).groupby(['subj_id', 'func.name', 'tpt', 'r_id'], sort=False).head(1)
    
    df_summ['p_data_x'] = ((1 - df_summ['p_lapse']) * df_summ['p_data_x'] +
                            df_summ['p_prev'] * norm.pdf(df_summ['pred_x'], 
                                                    loc=df_summ['prev_x'], 
                                                    scale=df_summ['sd_prev']) +
                            df_summ['p_rand'] * uniform.pdf(df_summ['pred_x'], 
                                                       loc=df_summ['min_x'], 
                                                       scale=df_summ['max_x'] - df_summ['min_x']))
        
    df_summ['p_data_y'] = ((1 - df_summ['p_lapse']) * df_summ['p_data_y'] +
                            df_summ['p_prev'] * norm.pdf(df_summ['pred_y'], 
                                                    loc=df_summ['prev_y'], 
                                                    scale=df_summ['sd_prev']) +
                            df_summ['p_rand'] * uniform.pdf(df_summ['pred_y'], 
                                                        loc=df_summ['min_y'], 
                                                        scale=df_summ['max_y'] - df_summ['min_y']))
    
    return df_summ




def compute_ll(df_participant_model):
    # Function to minimize
    def fn(pars):
        
        df_result = df_optim
        df_result['p_lapse'], df_result['sd_motor'], df_result['sd_prev'], df_result['p_rand0'] = pars
        df_result['p_rand'] = df_result['p_lapse'] * df_result['p_rand0']
        df_result['p_prev'] = df_result['p_lapse'] * (1 - df_result['p_rand0'])
        
        df_result = compute_p_data(df_result)
        
        if np.any(df_result['p_data_x'] <= 0) or np.any(df_result['p_data_y'] <= 0):
            print("Warning: Zero or negative values in p_data_x or p_data_y!")
            print(df_result[df_result['p_data_x'] <= 0])
            print(df_result[df_result['p_data_y'] <= 0])
            
        df_result['LL'] = np.log(df_result['p_data_x']) + np.log(df_result['p_data_y'])
        return -np.nansum(df_result['LL'])

    # Iterate thru subjects
    subj_param_dict = {}
    for subj in df_participant_model['subj_id'].unique():
        init_pars = [0.2, 0.08, 0.08, 0.1]
        bounds = [(0, 0.99), (1e-5, 1), (1e-5, 1), (0,1)]
        
        global df_optim
        df_optim = df_participant_model[df_participant_model['subj_id'] == subj].copy()
        df_optim = df_optim[df_optim['tpt'] > 2]
        
        res = minimize(fn, init_pars, bounds=bounds, options={'disp': False})
        if not res.success:
            print(f"Optimization failed for subject {subj}: {res.message}")
        
        pars = res.x             
        subj_param_dict[subj] = pars

    def apply_params(row):
        pars = subj_param_dict[row['subj_id']]
        return pd.Series({'p_lapse': pars[0], 'sd_motor': pars[1], 'sd_prev': pars[2], 'p_rand0': pars[3]})
    
    df_result = df_participant_model.copy()
    df_result = df_result.join(df_result.apply(apply_params, axis=1))
    df_result['p_rand'] = df_result['p_lapse'] * df_result['p_rand0']
    df_result['p_prev'] = df_result['p_lapse'] * (1 - df_result['p_rand0'])
    df_result = df_result[df_result['tpt'] > 2]
    df_result = compute_p_data(df_result)
    df_result['LL'] = np.log(df_result['p_data_x']) + np.log(df_result['p_data_y'])


    print(np.nansum(df_result['LL']))
    return df_result


def run_test():
    for participant_name in ["kids", "adults",  "monkeys"]:
        for model_name in ["transformer_" + str(i) for i in [1,2,3,4,5,6,8,10,13]]+ ["lot", "lot_nonrecursive", "gp", "comp_gp", "ridge", "linear", "linear_or_prev"]:
            print(participant_name)
            print(model_name)
            df_participant_model = pd.read_csv("preprocessed_data/model_likelihoods/preprocessing/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "string"})
            out_path = "preprocessed_data/model_likelihoods/" + model_name + "_" + participant_name + ".csv"
            df_res = compute_ll(df_participant_model)
            df_res.to_csv(out_path, index=False)

def run_monkey_train():
    for participant_name in ["monkeys_train"]:
        for model_name in ["transformer_" + str(i) for i in [1,2,3,4,5,6,8,10,13]]:
            print(participant_name)
            print(model_name)
            df_participant_model = pd.read_csv("preprocessed_data/model_likelihoods/monkey_training/preprocessing/" + model_name + "_" + participant_name + ".csv", dtype={"func.name": "string"})
            out_path = "preprocessed_data/model_likelihoods/monkey_training/" + model_name + "_" + participant_name + ".csv"
            df_res = compute_ll(df_participant_model)
            df_res.to_csv(out_path, index=False)

if __name__=="__main__":
    run_test()
    run_monkey_train()
