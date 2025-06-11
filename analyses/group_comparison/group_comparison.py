import numpy as np
from sklearn.mixture import BayesianGaussianMixture
import pandas as pd
from scipy.stats import multivariate_normal, norm, uniform
from scipy.optimize import minimize
import matplotlib.pyplot as plt
import json

def plot_gmm(func, tpt, df):
    data = df[df["func.name"]==func]
    data = data[data["tpt"]==tpt]
    gmm = BayesianGaussianMixture(n_components=10,
                                  covariance_type='full',
                                  weight_concentration_prior_type='dirichlet_process',
                                  random_state=0)
    gmm.fit(data[['pred_x', 'pred_y']].values)

    xmin = np.mean(data["min_x"])
    xmax = np.mean(data["max_x"])
    ymin = np.mean(data["min_y"])
    ymax = np.mean(data["max_y"])
    # Generate grid for density estimation
    X, Y = np.mgrid[xmin:xmax:100j, ymin:ymax:100j]
    positions = np.vstack([X.ravel(), Y.ravel()])
    log_density = gmm.score_samples(positions.T)  # log-density for each position
    Z = np.exp(log_density).reshape(X.shape)      # Convert to density and reshape

    fig, ax = plt.subplots()
    ax.imshow(np.rot90(Z), cmap=plt.cm.gist_earth_r,
            extent=[xmin, xmax, ymin, ymax])
    #ax.plot(data["pred_x"], data["pred_y"], 'k.', markersize=5)
    ax.set_xlim([xmin, xmax])
    ax.set_ylim([ymin, ymax])
    plt.show()


# we have mean vector and cov matrix for each func/tpt
def compute_lik(gmms, subj_df, out_path):
    sm = 1e-10

    def compute_p_data(single_subj_df): 
        # Compute p subj data given params
        def row_lik(row):
            func = row["func.name"]
            t = row["tpt"]
            prediction = [row["pred_x"], row["pred_y"]]
            cov_add = np.array([[row["sd_motor"]**2, 0], [0, row["sd_motor"]**2]])
            
            lik = 0
            for i in range(len(gmms[func][t]["weights"])):
                dist = multivariate_normal(mean=gmms[func][t]["means"][i], cov=gmms[func][t]["covs"][i]+cov_add)
                lik += gmms[func][t]["weights"][i] * dist.pdf(prediction)
            lik = sm + ((1-sm) * lik)
            lapse_lik = (row["p_prev"] * norm.pdf(prediction[0], loc=row["prev_x"], scale=row["sd_prev"]) * norm.pdf(prediction[1], loc=row["prev_y"], scale=row["sd_prev"])) + ((1-row["p_prev"]) * uniform.pdf(prediction[0], loc=row["min_x"], scale=row["max_x"]) * uniform.pdf(prediction[1], loc=row["min_y"], scale=row["max_y"]))
            
            prediction_lik = ((1-row["p_lapse"])*lik) + (row["p_lapse"]*lapse_lik)
            
            return np.log(prediction_lik)
            
        return single_subj_df.apply(row_lik, axis=1)
          
             
    def fn(pars):
        
        p_lapse, p_rand0, sd_motor, sd_prev = pars
        p_prev = p_lapse * (1 - p_rand0) 
        df_optim["p_lapse"] = p_lapse
        df_optim["p_prev"] = p_prev
        df_optim["sd_motor"] = sd_motor
        df_optim["sd_prev"] = sd_prev
        
        LL_vec = compute_p_data(df_optim)
        return -np.sum(LL_vec)


    subj_param_dict = {}
    for subj in subj_df['subj_id'].unique():
        # p_lapse, p_rand, sd_motor, sd_prev
        init_pars = [0.1, 0.1, 0.1, 0.1]
        bounds = [(1e-5, 1-(1e-5)), (1e-5, 1-(1e-5)), (1e-5, 1), (1e-5, 1)]

        global df_optim
        df_optim = subj_df[subj_df['subj_id'] == subj]
        df_optim = df_optim[df_optim["tpt"]>2]
        
        res = minimize(fn, init_pars, bounds=bounds, options={'disp': False})
        if not res.success:
            print(f"Optimization failed for subject {subj}: {res.message}")
        #print(res)
        pars = res.x             
        subj_param_dict[subj] = pars

    def apply_params(row):
        pars = subj_param_dict[row['subj_id']]
        return pd.Series({'p_lapse': pars[0],  'p_rand0': pars[1], 'sd_motor': pars[2], 'sd_prev': pars[3]})
    
    # construct result df
    df_result = subj_df.copy()
    df_result = df_result.join(df_result.apply(apply_params, axis=1))
    df_result['p_rand'] = df_result['p_lapse'] * df_result['p_rand0']
    df_result['p_prev'] = df_result['p_lapse'] * (1 - df_result['p_rand0']) 
    
    df_result['LL'] = compute_p_data(df_result)

    print(np.nansum(df_result['LL']))
    df_result.to_csv(out_path, index=False)
  
  
  
def compute_gmms(comparison_df):
    gmms = {}
    for (func, tpt), comp_group in comparison_df.groupby(['func.name', 'tpt']):        

        # Fit GMM with dirichlet process prior, max 10 components
        gmm = BayesianGaussianMixture(n_components=len(comp_group['pred_x']),
                                      covariance_type='full',
                                      weight_concentration_prior_type='dirichlet_process',
                                      random_state=0)
        gmm.fit(comp_group[['pred_x', 'pred_y']].values)
        
        # Store fit params
        gmms[func] = gmms.get(func, {})
        gmms[func][tpt] = {}
        gmms[func][tpt]["means"] = gmm.means_
        gmms[func][tpt]["covs"] = gmm.covariances_
        gmms[func][tpt]["weights"] = gmm.weights_
        print([round(w,3) for w in sorted(list(gmm.weights_))])
    return gmms



def rescale_dfs(df1, df2, df3):
    """
    Want all dfs on the same scale 
    Rn they are all on the same arbitrary scale, i.e. true_x is the same
    But we want to rescale between 0 and 1
    To do so we take the most extreme x and y bounds across dfs,
    Transform x bounds to 0 and 1,
    And apply the same transformation to y bounds
    """
    df1 = df1[df1["tpt"]>2].copy()
    df2 = df2[df2["tpt"]>2].copy()
    df3 = df3[df3["tpt"]>2].copy()
    
    dfs = [df1,df2,df3] 
    for func in pd.unique(df3["func.name"]):
        # get min and max bounds
        max_x = max([max(df[df["func.name"]==func]["max_x"]) for df in dfs])
        max_y = max([max(df[df["func.name"]==func]["max_y"]) for df in dfs])
        min_x = min([min(df[df["func.name"]==func]["min_x"]) for df in dfs])
        min_y = min([min(df[df["func.name"]==func]["min_y"]) for df in dfs])
        for df in dfs:
            mask = df["func.name"]==func
            df.loc[mask, "max_x"] = max_x
            df.loc[mask, "max_y"] = max_y
            df.loc[mask, "min_x"] = min_x
            df.loc[mask, "min_y"] = min_y
            
    for df in dfs:
        df['scale_by'] = df['max_x']-df['min_x']
        df['pred_x'] = (df['pred_x']-df['min_x'])/df['scale_by']
        df['pred_y'] = (df['pred_y']-df['min_y'])/df['scale_by']
        df['prev_x'] = (df['prev_x']-df['min_x'])/df['scale_by']
        df['prev_y'] = (df['prev_y']-df['min_y'])/df['scale_by']
        df['max_y'] = (df['max_y']-df['min_y'])/df['scale_by']
        df['min_y'] = 0
        df['max_x'] = 1
        df['min_x'] = 0
    return dfs


# Goal: compute prob of each kid's predictions under distributions of adult and monkey predictions
# To do so, we:
#   Group adult and monkey data by func and tpt
#   Fit mixture of gaussians to data
#   At first, lets just score kids under these
#   Alternatively:
#       Record means, covariance matrices, and weights
#       Run likelihood analysis on each kid using scipy, fitting motor error/lapse parameters
if __name__=="__main__":
    # load and preprocess monkey, adult, and kid data
    df_kid = pd.read_csv('../data/participants/kids_chs.csv')
    df_kid = df_kid.rename(columns={"response_x":"pred_x", "response_y":"pred_y", "seq_id":"func.name", "subject_id":"subj_id"})
    df_adult = pd.read_csv('../data/participants/adults.csv')
    df_adult = df_adult.rename(columns={"response_x":"pred_x", "response_y":"pred_y", "seq_id":"func.name", "subject_id":"subj_id"})
    df_monkey = pd.read_csv('../data/participants/monkeys_all.csv')
    df_monkey = df_monkey.rename(columns={"x_next": "true_x", "y_next": "true_y", "x_curr": "prev_x", "y_curr": "prev_y", "x_pred": "pred_x",
                                          "y_pred": "pred_y", "monkey_name": "subj_id", "func_id": "func.name", "n": "tpt"})
    df_monkey["func.name"] = df_monkey["func.name"].replace("example_line", "line")
    # keep common funcs
    df_kid = df_kid[df_kid["func.name"].isin(pd.unique(df_adult["func.name"]))]
    
    # scale prev x/y, pred x/y, min/max x/y
    df_kid, df_adult, df_monkey = rescale_dfs(df_kid, df_adult, df_monkey)

    df_kid.to_csv("scaled_kid.csv", index=False)
    df_adult.to_csv("scaled_adult.csv", index=False)
    df_monkey.to_csv("scaled_monkey.csv", index=False)
    
    adult_gmms = compute_gmms(df_adult)
    #print("-------------")
    #monkey_gmms = compute_gmms(df_monkey)
    
    #with open('monkey_gmms.json', 'w') as f:
    #    json.dump(monkey_gmms, f)
    
    #plot_gmm("sine", 8, df_adult)
    
    compute_lik(adult_gmms, df_kid, "p_adult.csv")
    
    
    