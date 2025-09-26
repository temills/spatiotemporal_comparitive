include("utils.jl")
include("proposals.jl")
import LinearAlgebra
using CSV
using DataFrames
using Plots

function plot_function(xs, ys, all_xs_model, all_ys_model)
    rng_x = maximum(xs) - minimum(xs)
    rng_y = maximum(ys) - minimum(ys)

    fig = plot( xlim=(minimum(xs)-rng_x*0.15,maximum(xs)+rng_x*0.15), 
        ylim=(minimum(ys)-rng_y*0.15,maximum(ys)+rng_y*0.15), size=(1000,600))
    plot!(fig, xtickfont=font(18), 
            ytickfont=font(18), 
            guidefont=font(18), 
            legendfont=font(18))

    max_alpha = min((1/length(all_ys_model)),0.5)
    for i in 1:length(all_ys_model)
        pred_xs = all_xs_model[i]
        pred_ys = all_ys_model[i]
        plot!(fig, pred_xs, pred_ys, color="orange", fillalpha=(0.25*max_alpha),markeralpha=0.5*max_alpha,
                        linealpha=max_alpha,
                        linewidth=3, label=nothing, dpi=300)
    end

    scatter!(fig, xs, ys,c="black", label="Data",ms=5,
                     markeralpha=0.5,dpi=300)
    gui(fig)

end

function evaluate_function(terms::Vector{Vector{Int64}}, weights_x::Vector{Float64},
                            weights_y::Vector{Float64}, xs::Vector{Float64}, ys::Vector{Float64}, ts_std::Vector{Float64})
    pred_xs = [xs[1]]
    pred_ys = [ys[1]]

    for t in 1:(length(xs))
        vars = [ts_std[t], xs[t], ys[t]]
        pred_x = evaluate_polynomial(vars, weights_x, terms)
        pred_y = evaluate_polynomial(vars, weights_y, terms)
        push!(pred_xs, pred_x)
        push!(pred_ys, pred_y)
    end
    return pred_xs, pred_ys;
end;

function evaluate_function_extended(terms::Vector{Vector{Int64}}, weights_x::Vector{Float64},
    weights_y::Vector{Float64}, xs::Vector{Float64}, ys::Vector{Float64}, ts_std::Vector{Float64})
    pred_xs = [xs[1]]
    pred_ys = [ys[1]]

    for t in 1:(length(ts_std))
        if t <= length(xs)
            vars = [ts_std[t], xs[t], ys[t]]
        else
            vars = [ts_std[t], pred_xs[end], pred_ys[end]] 
        end
        pred_x = evaluate_polynomial(vars, weights_x, terms)
        pred_y = evaluate_polynomial(vars, weights_y, terms)
        push!(pred_xs, pred_x)
        push!(pred_ys, pred_y)

    end
    return pred_xs, pred_ys;
end;

@gen function model(terms::Vector{Vector{Int64}},  xs::Vector{Float64}, ys::Vector{Float64}, ts_std::Vector{Float64})

    n_terms = length(terms)
    weight_precision_shape = ({:weight_shape} ~ gamma(1,1))
    weight_precision_scale = ({:weight_scale} ~ gamma(1,1))

    weight_precision = ({:weight_precision} ~ gamma(weight_precision_shape,weight_precision_scale))

    cov_mat = Matrix((1/√weight_precision) * LinearAlgebra.I, n_terms, n_terms)

    weights_x = ({:weights_x} ~ mvnormal(zeros(n_terms), cov_mat))
    weights_y = ({:weights_y} ~ mvnormal(zeros(n_terms), cov_mat))

    α = ({:shape} ~ gamma(1,1))
    β = ({:scale} ~ gamma(10,10))
    τ_x = ({:precision_x} ~ gamma(α,β))
    τ_y = ({:precision_y} ~ gamma(α,β))

    std_x = √(1/τ_x)
    std_y = √(1/τ_y)

    pred_xs, pred_ys = evaluate_function(terms, weights_x, weights_y, xs, ys, ts_std)
    for t in 1:(length(xs)-1)
        ({(:x, t)} ~ normal(pred_xs[t+1], std_x))
        ({(:y, t)} ~ normal(pred_ys[t+1], std_y))

    end

    return weights_x, weights_y, std_x, std_y
end

function run_mcmc(trace, terms,xs, ys,ts_std, n_mcmc; vis=false)
    all_ys_model = Vector{Vector{Float64}}()
    all_xs_model = Vector{Vector{Float64}}()

    for iter=0:(n_mcmc)
        (trace, _) = mh(trace, weights_proposal, ())
        for _=1:3
            (trace, _) = mh(trace, noise_proposals, ())
            (trace, _) = mh(trace, weight_noise_proposals, ())
            (trace, _) = mh(trace, Gen.select(:weights_x))
            (trace, _) = mh(trace, Gen.select(:weights_y))
        end

        if (iter % 2500 == 0) & vis
            weights_x, weights_y = trace[:weights_x], trace[:weights_y]
            xs_model, ys_model = evaluate_function(terms, weights_x, weights_y, xs, ys, ts_std)
            push!(all_xs_model, copy(xs_model))
            push!(all_ys_model, copy(ys_model))
            all_xs_model = last(all_xs_model,5)
            all_ys_model = last(all_ys_model,5)

            plot_function( xs, ys, all_xs_model, all_ys_model)
            println(iter)
            println(weights_x)
            println(weights_y)
            println("")
        end
    end
    return trace
end

function run(model,terms, xs, ys,ts_std, n_mcmc; vis=false)
    observations = Gen.choicemap()
    for t in 1:(length(xs)-1)
        observations[(:x, t)] = xs[t+1]
        observations[(:y, t)] = ys[t+1]
    end
    (trace, _) = generate(model, (terms,xs,ys, ts_std), observations)
    run_mcmc(trace, terms,xs, ys, ts_std, n_mcmc, vis=vis)
end