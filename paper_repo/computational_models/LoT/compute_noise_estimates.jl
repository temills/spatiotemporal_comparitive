include("main.jl")
using Base.Filesystem
using JSON

"""
* Trace scores are marginalized over gamma distribution with hyper params α and β
* Given trace and data at a given timepoint:
    * evaluate function
    * compute posterior over noise
    * P(noise|func, data) ∝ P(data | noise, func) * P(noise)
"""

data_path = "output/"
seq_dict = JSON.parsefile("../stimuli.json")["funcs"]

function scale_pts(xs, ys)
    distances = [sqrt((xs[i+1] - xs[i])^2 + (ys[i+1] - ys[i])^2) for i in 1:length(xs)-1]
    mean_dist = mean(distances)
    xs = xs./mean_dist
    ys = ys./mean_dist
    return xs, ys
end

function gamma_posterior_update(pred_val::Vector{Float64}, true_val::Vector{Float64}, shape_0::Float64, scale_0::Float64)
    """
    Gamma distribution is conjugate prior to gamma distribution, from which we sample precision
    The prior and posterior distributions of precision are Gamma distributions
    Closed form posterior update: https://www.cs.ubc.ca/~murphyk/Papers/bayesGauss.pdf
    """
    n = length(pred_val)
    sqr_error = (pred_val - true_val).^2

    shape = shape_0 + (n/2)

    rate_0 = 1/scale_0
    rate = rate_0 + sum(sqr_error)/2
    scale = 1/rate

    return shape, scale
end


function add_sd_to_data()
    move_from_true = true
    l = []
    for filename in readdir(data_path)
        if isdir(data_path * filename) || occursin("scores", filename)
            continue
        end

        println(filename)

        df = DataFrame(CSV.File(data_path * filename))
        df = df[.!((df.tpt .> 1) .& (df.sample .!= 100000)), :]
        seq_name = filename[1:end-4]   
        seq_info = seq_dict[seq_name]

        xs = Vector{Float64}(seq_info["true_coords"][1])
        ys = Vector{Float64}(seq_info["true_coords"][2])
        xs, ys = scale_pts(xs, ys)
        sampled_sd_xs = []
        sampled_sd_ys = []
        sd_xs = []
        sd_ys = []
        for row_idx=1:size(df, 1)
            row = df[row_idx, :]
            if ismissing(row.tpt) || row.tpt == 0
                push!(sd_xs, missing)
                push!(sd_ys, missing)
                push!(sampled_sd_xs, missing)
                push!(sampled_sd_ys, missing)
                continue
            end
            func = str2node(row.func)
            init_speed = row.init_speed
            init_angle = row.init_angle
            shape_0_x = row.shape_x
            scale_0_x = row.scale_x
            shape_0_y = row.shape_y
            scale_0_y = row.scale_y
            # at tpt t, we've seen xs 1-t+1, and we generate t points
            n_to_predict = row.tpt - 1
            pred_xs, pred_ys = evaluate_function(func, n_to_predict, xs[1:row.tpt], ys[1:row.tpt], init_speed, init_angle, move_from_true)
            shape_x, scale_x = gamma_posterior_update(pred_xs, xs[2:row.tpt], shape_0_x, scale_0_x)
            shape_y, scale_y = gamma_posterior_update(pred_ys, ys[2:row.tpt], shape_0_y, scale_0_y)
            # compute mean precision
            μ_τ_x = shape_x*scale_x
            μ_τ_y = shape_y*scale_y
            # compute and store mean standard deviation
            sd_x = 1/μ_τ_x^0.5
            sd_y = 1/μ_τ_y^0.5
            append!(sd_xs, sd_x)
            append!(sd_ys, sd_y)
            # sample precision
            sampled_τ_x = Gen.gamma(shape_x, scale_x)
            sampled_τ_y = Gen.gamma(shape_y, scale_y)
            # compute and store sampled standard deviation
            sampled_sd_x = 1/sampled_τ_x^0.5
            sampled_sd_y = 1/sampled_τ_y^0.5
            append!(sampled_sd_xs, sampled_sd_x)
            append!(sampled_sd_ys, sampled_sd_y)
        end
        df.sampled_sd_x = sampled_sd_xs
        df.sampled_sd_y = sampled_sd_ys
        df.sd_x = sd_xs
        df.sd_y = sd_ys
            
        CSV.write(data_path * filename, df)

    end
end

add_sd_to_data()

