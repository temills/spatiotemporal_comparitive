import numpy as np
from scipy.stats import norm, multivariate_normal, wasserstein_distance_nd
import pandas as pd
import matplotlib.pyplot as plt
#import pickle as pkl
import sys
from memory_profiler import memory_usage
import itertools

# measure divergence between models 
# could prob speed things up by ignoring very low probability particles or combining 0 prob cells


def compute_pdf_model(particles, bin_centers_x, bin_centers_y):
    particles = particles.reset_index().to_dict(orient='list')
    # compute the weighted pdf for each bin for given distributions
    pdf = np.zeros((len(bin_centers_x), len(bin_centers_y)))
    for particle_idx in range(len(particles['pred_x'])):
        pdf_x = norm.pdf(bin_centers_x, particles["pred_x"][particle_idx], (particles["std_x"][particle_idx]**2 + motor_sd**2)**0.5)
        pdf_y = norm.pdf(bin_centers_y, particles["pred_y"][particle_idx], (particles["std_y"][particle_idx]**2 + motor_sd**2)**0.5)
        pdf_product = np.outer(pdf_x, pdf_y)
        pdf = pdf + (pdf_product * particles["posterior"][particle_idx])
    return pdf 

# same num bins for all tpts/patterns
# ignore particles that go off screen
def compute_pdfs_tpt(model1_particles, model2_particles, bin_centers_x, bin_centers_y): 
      
    # compute the weighted pdf for each bin for both distributions
    model1_pdf = compute_pdf_model(model1_particles, bin_centers_x, bin_centers_y) 
    model2_pdf = compute_pdf_model(model2_particles, bin_centers_x, bin_centers_y)
    # multiply each bin center pdf by cell area
    model1_pdf = model1_pdf * (bin_width**2)
    model2_pdf = model2_pdf * (bin_width**2)
    # normalize pdfs
    model1_pdf /= np.sum(model1_pdf)
    model2_pdf /= np.sum(model2_pdf)
    
    return model1_pdf, model2_pdf
    
    
def compute_kl_divergence(model1_pdf, model2_pdf):
    epsilon = 1e-20
    model1_pdf = np.maximum(model1_pdf, epsilon)
    model2_pdf = np.maximum(model2_pdf, epsilon)
    model1_pdf /= np.sum(model1_pdf)
    model2_pdf /= np.sum(model2_pdf)
    
    kl_div = np.sum(model1_pdf * np.log(model1_pdf / model2_pdf))
    return kl_div

#why error File "/usr/local/lib/python3.11/site-packages/scipy/stats/_stats_py.py", line 10339, in wasserstein_distance_nd return -opt_res.fun TypeError: bad operand type for unary -: 'NoneType'
#is it super slow with 1D?
#is it faster with samples instead of weights?

def compute_emd(model1_pdf, model2_pdf, bin_centers_x, bin_centers_y):
    model1_weights = model1_pdf.flatten()
    model2_weights = model2_pdf.flatten()
    indices_x, indices_y = np.meshgrid(range(len(bin_centers_x)), range(len(bin_centers_y)))
    values = np.stack((bin_centers_x[indices_x.flatten()], bin_centers_y[indices_y.flatten()]), axis=1)
    
    #weights is length n_cells
    #values is n_cells, 2
    #remove indices where both weights are 0
    v = 1e-6
    print(model1_weights<v)
    print(sum(model1_weights<v))
    print("-----------")
    print(model2_weights)
    print(model2_weights<v)
    print(sum(model2_weights<v))
    print(sum((model1_weights<v) & (model2_weights<v)))
     
    #print(values)
    print(np.shape(values))
    print(model1_weights)
    print(np.shape(model1_weights))
    # equivalent to:
    # model1_weights = []
    # model2_weights = []
    # values = []
    # for i in range(len(bin_centers_x)):
    #     for j in range(len(bin_centers_y)):
    #         model1_weights.append(model1_pdf[i,j])
    #         model2_weights.append(model2_pdf[i,j])
    #         values.append([bin_centers_x[i], bin_centers_y[j]])
    # epsilon = 1e-10
    # model1_pdf = np.maximum(model1_pdf, epsilon)
    # model2_pdf = np.maximum(model2_pdf, epsilon)
    emd = wasserstein_distance_nd(values, values, u_weights=model1_weights, v_weights=model2_weights)
    return emd


def compute_total_variation_distance(model1_pdf, model2_pdf):
    #1/2 sum of abs differences in probability for each event
    return np.sum(abs(model1_pdf - model2_pdf))/2
    

def plot_res(model1_pdf, model2_pdf, m1, m2, kl, emd):
    # plot distributions
    fig, axs = plt.subplots(1, 2, figsize=(12, 6))
    im1 = axs[0].imshow(model1_pdf, cmap='hot')
    axs[0].set_title(m1)
    im2 = axs[1].imshow(model2_pdf, cmap='hot')
    axs[1].set_title(m2)
    fig.colorbar(im1, ax=axs[0])
    fig.colorbar(im2, ax=axs[1])
    fig.suptitle("KL:" + str(round(kl,4)) + " EMD:" + str(round(emd,4)))
    plt.show()


def construct_df(model_names, model_pair, outfile, bin_centers_x, bin_centers_y):
    # read model data
    model_df = pd.read_csv('models.csv')
    
    try:
        prev_df = pd.read_csv(outfile, index_col=0)
        data = prev_df.to_dict(orient='list')
    except:
        data = {'n':[], 'model1':[], 'model2':[], 'func.name':[], 'kl':[], 'emd':[], 'tv':[]}  
        prev_df = pd.DataFrame(data) 
    if model_pair == None:
        # load existing divergence df
        model_1_list = model_names
        model_2_list = model_names
    else:
        model_1_list = model_pair
        model_2_list = model_pair
        
    
    # iterate thru models
    for model1_name in model_1_list:
        print("model 1:", model1_name)
        model1 = model_df[model_df["model"]==model1_name]
        for model2_name in model_2_list:
            print("model 2:", model2_name)
            model2 = model_df[model_df["model"]==model2_name]
            # iterate thru funcs
            for (i, func) in enumerate(pd.unique(model1['func.name'])):
                # continue if already computed
                if len(prev_df[(prev_df['model1']==model1_name) & (prev_df['model2']==model2_name) & (prev_df['func.name']==func)]['model1'])>0:
                    continue
                print("function " + str(i) + "/" + str(len(pd.unique(model1['func.name']))) + ": " + func)
                # iterate thru tpts
                for tpt in sorted(pd.unique(model1['n'])):
                    model1_tpt = model1[(model1['n']==tpt) & (model1['func.name']==func)]
                    model2_tpt = model2[(model2['n']==tpt) & (model2['func.name']==func)]
                    
                    # compute pdfs
                    model1_pdf, model2_pdf = compute_pdfs_tpt(model1_tpt, model2_tpt, bin_centers_x, bin_centers_y)
                    
                    # compute divergence
                    kl_div = compute_kl_divergence(model1_pdf, model2_pdf)
                    tv = compute_total_variation_distance(model1_pdf, model2_pdf)
                    #emd = compute_emd(model1_pdf, model2_pdf, bin_centers_x, bin_centers_y)
                    emd = None
                    # plot distributions
                    # plot_res(model1_pdf, model2_pdf, model1_name, model2_name, kl, tv)
                    
                    # store data
                    data['n'].append(tpt)
                    data['model1'].append(model1_name)
                    data['model2'].append(model2_name)
                    data['func.name'].append(func)
                    data['kl'].append(kl_div)
                    data['emd'].append(emd)
                    data['tv'].append(tv)
                df = pd.DataFrame(data)  
                df.to_csv(outfile) 
                    
    df = pd.DataFrame(data)  
    df.to_csv(outfile) 



def test(bin_centers_x, bin_centers_y):
    # read model data
    model_df = pd.read_csv('models.csv')
        
    # iterate thru models
    model1_name = "LoT"
    model1 = model_df[model_df["model"]==model1_name]
    model2_name = "GPSL"
    model2 = model_df[model_df["model"]==model2_name]
    # iterate thru funcs
    for (i, func) in enumerate(["triangle_1"]):#pd.unique(model1['func.name'])):
        print("function " + str(i) + "/" + str(len(pd.unique(model1['func.name']))) + ": " + func)
        # iterate thru tpts
        for tpt in sorted(pd.unique(model1['n'])):
            model1_tpt = model1[(model1['n']==tpt) & (model1['func.name']==func)]
            model2_tpt = model2[(model2['n']==tpt) & (model2['func.name']==func)]
            # compute pdfs
            model1_pdf, model2_pdf = compute_pdfs_tpt(model1_tpt, model2_tpt, bin_centers_x, bin_centers_y)
            # compute divergence
            kl= compute_kl_divergence(model1_pdf, model2_pdf)
            tv = compute_total_variation_distance(model1_pdf, model2_pdf)
            emd = compute_emd(model1_pdf, model2_pdf, bin_centers_x, bin_centers_y)
            #emd = None
            # plot distributions
            plot_res(model1_pdf, model2_pdf, model1_name, model2_name, kl, tv)
            

def compute_divergence():
    bin_edges = np.arange(0, 1+bin_width, bin_width)
    bin_centers = (bin_edges[:-1] + bin_edges[1:]) / 2
    model_names = ['Lin', 'LoT', 'GPSL', 'GPNC', 'Ridge', 'GPSL_new', 'GPNC_new']
    
    if len(sys.argv) > 1:
        i = int(sys.argv[1])
        model_pairs = []
        for n1 in model_names:
            for n2 in model_names:
                if n1==n2:
                    continue
                model_pairs.append([n1, n2])
        for n in model_names:
            model_pairs.append([n,n]) 
        model_pair = model_pairs[i]
        outfile = str(i) + ".csv"
    else:
        outfile = "div.csv"
        model_pair = None
    construct_df(model_names, model_pair, outfile, bin_centers, bin_centers)
    
def run_test():
    bin_edges = np.arange(0, 1+bin_width, bin_width)
    bin_centers = (bin_edges[:-1] + bin_edges[1:]) / 2
    test(bin_centers, bin_centers)


def select_stimuli():
    df = pd.read_csv('preprocessed_div.csv')
    all_func_sets = list(itertools.combinations(pd.unique(df["func.name"]), 5))
    data = {'func_set' : [], 'model_pair' : [], 'mean_kl' : [], 'all_kl' : [], 'min_kl' : [], 'max_kl' : []}
    for (i, fs) in enumerate(all_func_sets):
        for mp in pd.unique(df["model_pair"]):
            
            kls = []
            #get div for each func in func set
            for func in fs:
                tmp = df[(df['model_pair']==mp) & (df['func.name']==func)].reset_index().to_dict(orient='list')
                assert(len(tmp["mean_sym_kl"])==1)
                kls.append(tmp["mean_sym_kl"][0])
            
            data['func_set'].append(fs)
            data['model_pair'].append(mp)
            data['all_kl'].append(kls)
            data['mean_kl'].append(np.mean(kls))
            data['min_kl'].append(min(kls))
            data['max_kl'].append(max(kls))
        if i%100==0:
            print(i, "/", len(all_func_sets))
            print(fs)
    df = pd.DataFrame(data)  
    df.to_csv("div_by_set.csv") 


if __name__=="__main__":
    motor_sd = 0.021
    bin_width = .001
    #compute_divergence()
    #run_test()
    select_stimuli()
    
       