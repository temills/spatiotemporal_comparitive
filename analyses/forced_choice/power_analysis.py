import pandas as pd


# For each pattern/tpt, get
#   true next point
#   linear extrapolation
#   linear predictions (means + sds)
#   LoT predictions (means + sds)
# Compute
#   P(linear|linear model)
#   P(linear|LoT model)
#   P(true|linear model)
#   P(true|LoT model)
#   P(true|LoT model)/P(linear|LoT model)
#   P(true|linear model)/P(linear|linear model)
# Then, for linear and LoT predictor, for each example, we have prob of that choice over the other, can do mixture with random:
#   p_LoT = p_rand*0.5 + (1-p_rand)*P(true|LoT)/(P(true|LoT)+P(linear|LoT))

if __name__=="__main__":
    # Filter stimuli
    df = pd.read_csv('../data/expt_stimuli.csv')
    all_funcs = df["func.name"].unique()
    abnormal_tpts = {
        "zigzag_3": 13,
        "zigzag_2": 13,
        "zigzag_1": 13,
        "3_pts": 12,
        "stairs_2": 12,
        "alternating_diff_2": 11,
        "sine": 12,
        "increasing_lines": 10,
        "radial_1": 13,
        "square_2": 13,
        "square_spiral": 12,
        "plus": 12,
        "radial_increasing": 11,
    }
    tpt_map = {
        fn: abnormal_tpts.get(fn, 14) for fn in all_funcs
    }
    df = df[df["tpt"] == df["func.name"].map(tpt_map)+1]
    
    # Now read model predictions
    lot_df = pd.read_csv("../data/models/lot.csv")
    lin_df = pd.read_csv("../data/models/linear_1.csv")
    
    # For each function, compute p_true under each model, and p_lin under each model
    # Df with function, tpt, p_true, p_lin, model
    
    
    
