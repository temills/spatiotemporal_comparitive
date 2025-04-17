import pandas as pd
import numpy as np
from scipy.stats import norm, uniform
from scipy.optimize import minimize

def compute_ll(df_participant_model, out_path, fit_rand=False, fit_lin=False):
    sm = 1e-10 

    def compute_p_data(df):
        def group_apply(group):
            group['p_data_x'] = norm.pdf(group['pred_x'], loc=group['model_pred_x'], 
                                         scale=np.sqrt(group['sd_motor']**2))
                                         #scale=np.sqrt(group['model_std_x']**2 + group['sd_motor']**2))
            group['p_data_x'] = sm + (1 - sm) * np.sum(group['model_posterior'] * group['p_data_x'])
            
            group['p_data_y'] = norm.pdf(group['pred_y'], loc=group['model_pred_y'], 
                                         scale=np.sqrt(group['sd_motor']**2))
                                         #scale=np.sqrt(group['model_std_y']**2 + group['sd_motor']**2))
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
        
        return df.groupby(['subj_id', 'func.name', 'n', 'r_id']).apply(group_apply)

    def fn(pars):
        if not fit_rand:
            pars = np.append(pars, 0)
        if not fit_lin:
            pars = np.append(pars, 0)
            pars = np.append(pars, 0.1)
        
        df_result = df_optim.copy()
        df_result['p_lapse'], df_result['sd_motor'], df_result['sd_prev'], df_result['p_rand0'], df_result['p_lin0'], df_result['sd_lin'] = pars
        df_result['p_rand'] = df_result['p_lapse'] * df_result['p_rand0']
        df_result['p_prev'] = df_result['p_lapse'] * (1 - df_result['p_rand0']) * (1-df_result['p_lin0'])
        df_result['p_lin'] = df_result['p_lapse'] * (1 - df_result['p_rand0']) * (df_result['p_lin0'])
        
        df_result = df_result[df_result['n'] > 2]
        df_result = compute_p_data(df_result)
        
        
        if np.any(df_result['p_data_x'] <= 0) or np.any(df_result['p_data_y'] <= 0):
            print("Warning: Zero or negative values in p_data_x or p_data_y!")
            print(df_result[df_result['p_data_x'] <= 0])
            print(df_result[df_result['p_data_y'] <= 0])
            
        df_result['LL'] = np.log(df_result['p_data_x']) + np.log(df_result['p_data_y'])
        return -np.nansum(df_result['LL'])

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
    df_result.to_csv(out_path, index=False)


for model_name in ["ss", "lot", "gpnc", "gpsl", "ridge", "lin"]: #"lot_no_recursion",
    print(model_name)
    for participant_name in ["kid_chs"]: #,"monkey", "kid", "adult"]:
        print(participant_name)
        df_participant_model = pd.read_csv("preprocessed_data/" + model_name + "_" + participant_name + ".csv")
        out_path = "model_fits/LLs2/" + model_name + "_" + participant_name + ".csv"
        compute_ll(df_participant_model, out_path, True, False)


