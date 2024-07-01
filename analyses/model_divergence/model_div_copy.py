import numpy as np
from scipy.stats import norm, multivariate_normal, wasserstein_distance_nd
import pandas as pd
import matplotlib.pyplot as plt
import pickle as pkl

#Measure divergence between models on different patterns
#In python, to avoid pain and suffering


#could prob speed things up by ignoring very low probability particles or combining 0 prob cells
#could also make pdf comp faster without loops


bin_width = .001


def compute_pdf_model(particles, bin_centers_x, bin_centers_y):
    particles = particles.reset_index().to_dict(orient='list')
    # Compute the weighted pdf for each bin for given distributions
    pdf = np.zeros((len(bin_centers_x), len(bin_centers_y)))
    for particle_idx in range(len(particles['pred_x'])):
        #mean_x = particles["pred_x"][particle_idx]
        #mean_y = particles["pred_y"][particle_idx]
        #std_x = particles["std_x"][particle_idx]
        #std_y = particles["std_y"][particle_idx]
        #means = np.array([particles["pred_x"][particle_idx], particles["pred_y"][particle_idx]])
        #stds = np.array([particles["std_x"][particle_idx], particles["std_y"][particle_idx]])
        posterior = particles["posterior"][particle_idx]
        pdf_x = np.array([norm.pdf(x, particles["pred_x"][particle_idx], particles["std_x"][particle_idx]) for x in bin_centers_x])[:, np.newaxis]
        pdf_y = np.array([norm.pdf(y, particles["pred_y"][particle_idx], particles["std_y"][particle_idx]) for y in bin_centers_y])[np.newaxis, :]
        pdf = pdf + (pdf_x * pdf_y * posterior)
        #for i, x in enumerate(bin_centers_x):
        #    for j, y in enumerate(bin_centers_y):
                #p1 = multivariate_normal.pdf([x, y], means, np.diag(stds**2))
                #p2 = norm.pdf(x, mean_x, std_x) * norm.pdf(y, mean_y, std_y)
                #assert(np.isclose(p1, p2))
                #pdf[i, j] += posterior * norm.pdf(x, mean_x, std_x) * norm.pdf(y, mean_y, std_y)
    return pdf 

def compute_pdfs_tpt(model1_particles, model2_particles):    
    # Define the range and bins
    min_x = min(np.min(model1_particles['pred_x'] - 3 * model1_particles['std_x']),
                np.min(model2_particles['pred_x'] - 3 * model2_particles['std_x']))
    max_x = max(np.max(model1_particles['pred_x'] + 3 * model1_particles['std_x']),
                np.max(model2_particles['pred_x'] + 3 * model2_particles['std_x']))
    bins_x = np.arange(min_x, max_x+bin_width, bin_width)
    bin_centers_x = (bins_x[:-1] + bins_x[1:]) / 2
    min_y = min(np.min(model1_particles['pred_y'] - 3 * model1_particles['std_y']),
                np.min(model2_particles['pred_y'] - 3 * model2_particles['std_y']))
    max_y = max(np.max(model1_particles['pred_y'] + 3 * model1_particles['std_y']),
                np.max(model2_particles['pred_y'] + 3 * model2_particles['std_y']))
    bins_y = np.arange(min_y, max_y+bin_width, bin_width)
    bin_centers_y = (bins_y[:-1] + bins_y[1:]) / 2
    
    # Compute the weighted pdf for each bin for both distributions
    model1_pdf = compute_pdf_model(model1_particles, bin_centers_x, bin_centers_y) 
    model2_pdf = compute_pdf_model(model2_particles, bin_centers_x, bin_centers_y)
    # Multiply each bin center pdf by bin_area
    model1_pdf = model1_pdf * (bin_width**2)
    model2_pdf = model2_pdf * (bin_width**2)
    # Normalize pdfs
    model1_pdf /= np.sum(model1_pdf)
    model2_pdf /= np.sum(model2_pdf)
    
    return model1_pdf, model2_pdf, bin_centers_x, bin_centers_y
    
    
def compute_kl_divergence(model1_pdf, model2_pdf):
    epsilon = 1e-10
    model1_pdf = np.maximum(model1_pdf, epsilon)
    model2_pdf = np.maximum(model2_pdf, epsilon)
    kl_div = np.sum(model1_pdf * np.log(model1_pdf / model2_pdf)) #should multiply by bin_are?
    return kl_div

def compute_emd(model1_pdf, model2_pdf, bin_centers_x, bin_centers_y):
    # model1_weights = []
    # model2_weights = []
    # values = []
    # for i in range(len(bin_centers_x)):
    #     for j in range(len(bin_centers_y)):
    #         model1_weights.append(model1_pdf[i,j])
    #         model2_weights.append(model2_pdf[i,j])
    #         values.append([bin_centers_x[i], bin_centers_y[j]])
    # print("-----------")
    # print(model1_weights)
    # print(model2_weights)
    # print(values)
    model1_weights = model1_pdf.flatten()
    model2_weights = model2_pdf.flatten()
    indices_x, indices_y = np.meshgrid(range(len(bin_centers_x)), range(len(bin_centers_y)))
    values = np.stack((bin_centers_x[indices_x.flatten()], bin_centers_y[indices_y.flatten()]), axis=1)
    epsilon = 1e-10
    model1_pdf = np.maximum(model1_pdf, epsilon)
    model2_pdf = np.maximum(model2_pdf, epsilon)
    emd = wasserstein_distance_nd(values, values, u_weights=model1_weights, v_weights=model2_weights)
    return emd

def compute_total_variation_distance(model1_pdf, model2_pdf):
    #1/2 sum of abs diffeences in probability for each event
    return np.sum(abs(model1_pdf - model2_pdf))/2 #why is this always 0
    

def plot_res(model1_pdf, model2_pdf, m1, m2, kl, emd):
    fig, axs = plt.subplots(1, 2, figsize=(12, 6))
    im1 = axs[0].imshow(model1_pdf, cmap='hot')
    axs[0].set_title(m1)
    im2 = axs[1].imshow(model2_pdf, cmap='hot')
    axs[1].set_title(m2)
    fig.colorbar(im1, ax=axs[0])
    fig.colorbar(im2, ax=axs[1])
    fig.suptitle("KL:" + str(round(kl,4)) + " EMD:" + str(round(emd,4)))
    plt.show()

def construct_df(model_names):
    model_df = pd.read_csv('/Users/traceymills/Dropbox (MIT)/cocosci_projects/dots/spatiotemporal_comparitive/analyses/model_divergence/models.csv')
    try:
        prev_df = pd.read_csv('/Users/traceymills/Dropbox (MIT)/cocosci_projects/dots/spatiotemporal_comparitive/analyses/model_divergence/div.csv', index_col=0)
        data = prev_df.to_dict(orient='list')
    except:
        data = {'n':[], 'model1':[], 'model2':[], 'func.name':[], 'kl':[], 'emd':[], 'tv':[]}  
        prev_df = pd.DataFrame(data) 
    for model1_name in model_names:
        print("model 1:", model1_name)
        model1 = model_df[model_df["model"]==model1_name]
        for model2_name in model_names:
            print("model 2:", model2_name)
            model2 = model_df[model_df["model"]==model2_name]
            #iterate thru funcs
            for (i, func) in enumerate(pd.unique(model1['func.name'])):
                x = prev_df[(prev_df['model1']==model1_name) & (prev_df['model2']==model2_name) & (prev_df['func.name']==func)]['model1']
                if len(x)>0:
                    continue
                print("function " + str(i) + "/" + str(len(pd.unique(model1['func.name']))) + ": " + func)
                #iterate thru tpts
                for tpt in sorted(pd.unique(model1['n'])):
                    #print("tpt ", tpt)
                    model1_tpt = model1[(model1['n']==tpt) & (model1['func.name']==func)]
                    model2_tpt = model2[(model2['n']==tpt) & (model2['func.name']==func)]
                    #print("computing pdfs")
                    model1_pdf, model2_pdf, bin_centers_x, bin_centers_y = compute_pdfs_tpt(model1_tpt, model2_tpt)
                    print("n bins x:", len(bin_centers_x))
                    print("n bins y:", len(bin_centers_y))
                    #plot_res(model1_pdf, model2_pdf, model1_name, model2_name, 0, 0)
                    kl_div = compute_kl_divergence(model1_pdf, model2_pdf)
                    #emd = compute_emd(model1_pdf, model2_pdf, bin_centers_x, bin_centers_y)
                    emd = -1
                    tv = compute_total_variation_distance(model1_pdf, model2_pdf)
                    
                    data['n'].append(tpt)
                    data['model1'].append(model1_name)
                    data['model2'].append(model2_name)
                    data['func.name'].append(func)
                    data['kl'].append(kl_div)
                    data['emd'].append(emd)
                    data['tv'].append(tv)
                    #store pdfs
                #     pdfs['n'].append(tpt)
                #     pdfs['model1'].append(model1_name)
                #     pdfs['model2'].append(model1_name)
                #     pdfs['func.name'].append(func)
                #     pdfs['model1_pdf'].append(model1_pdf)
                #     pdfs['model2_pdf'].append(model2_pdf)
                #     pdfs['bin_centers_x'].append(bin_centers_x)
                #     pdfs['bin_centers_y'].append(bin_centers_y)
                #     pdfs['bin_width'].append(bin_width)
                # pkl.dump(pdfs, open('pdfs.pkl', 'wb'))
                #print(data)
                #for (k,v) in data.items():
                #    print(k)
                #    print(len(v))
                df = pd.DataFrame(data)  
                df.to_csv('div.csv') 
                    
    df = pd.DataFrame(data)  
    df.to_csv('div.csv') 

if __name__=="__main__":
    model_names = ['Lin', 'LoT', 'GPSL', 'GPNC', 'Ridge']
    construct_df(model_names)
       