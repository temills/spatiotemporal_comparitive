include("grammar.jl")
include("utils.jl")
include("tDistribution.jl")
using CSV
using DataFrames
using Plots
using LinearAlgebra
using Serialization


""" This file contains the model and code to run smc """


""" Define priors """
@gen function init_angle_proposal(trace::Trace)
    init_angle ~ normal(trace[:init_angle], 0.1)
end
@dist speed_proposal_dist(x::Float64) = exp(normal(log(x), 0.25))

@gen function init_speed_proposal(trace)
    init_speed ~ speed_proposal_dist(trace[:init_speed])
end
@dist number_prior_dist() = normal(0, 3)

@gen function pcfg_prior(type_dist::String, parent_tp::String, parent_c::Int64, env::Vector{String})
    probs = copy(dist_dict[type_dist])
    if length(env)>0
        bv_probs = map(v -> Float64(v==type_dist), env)
        if sum(bv_probs)>0
            append!(probs, normalize(bv_probs))
            probs = normalize(probs)
        end
    end
    t = @trace(categorical(probs), :type)
    if t > length(node_list)
        i = t - length(node_list)
        node = Node("bv_$i", parent_tp, parent_c, [], Vector{Node}())
        return node
    end
    node_type = node_list[t]
    child_types = grammar[node_type]["child_types"]
    children = Vector{Node}()
    params = []
    if node_type == "real"
        param = @trace(number_prior_dist(), :param)
        push!(params, param)
    elseif node_type == "int"
        param = @trace(int_prior_dist(), :int_param)
        push!(params, param)
    end
    new_env = copy(env)
    if node_type in ["lambda_op", "lambda_expr"]
        bv_type = "expr"
        push!(new_env, bv_type)
    end
    if length(child_types) > 0
        c1 = @trace(pcfg_prior(child_types[1], node_type, 1, new_env), :c1)
        push!(children, c1)
    end
    if length(child_types) > 1
        c2 = @trace(pcfg_prior(child_types[2], node_type, 2, new_env), :c2)
        push!(children, c2)
    end
    node = Node(node_type, parent_tp, parent_c, params, children)
    return node
end

@gen function sample_student_t(μ, α, β, n)
    ν = 2 * α
    σ = sqrt(1 / (β * n))
    v ~ student_t(μ, σ, ν)
end

@gen function model(xs::Vector{Float64}, ys::Vector{Float64})
    """ 
    Generative model, outputs a function
    """
    init_angle ~ uniform(-4, 4)
    init_speed ~ exponential(0.5)

    func = @trace(pcfg_prior("op", "root", 1, Vector{String}()), (:tree, 1))
    n_to_predict = length(xs)-1
    out_x, out_y = evaluate_function(func, n_to_predict, xs, ys, init_angle, init_speed)

    α_x = @trace(gamma(8, 8), :shape_x)
    β_x = @trace(gamma(2, 10), :scale_x)
    α_y = @trace(gamma(8, 8), :shape_y)
    β_y = @trace(gamma(2, 10), :scale_y)
    @trace(Map(sample_student_t)(out_x, fill(α_x, n_to_predict), fill(β_x, n_to_predict), fill(n_to_predict, n_to_predict)), :x)
    @trace(Map(sample_student_t)(out_y, fill(α_y, n_to_predict), fill(β_y, n_to_predict), fill(n_to_predict, n_to_predict)), :y)

    return func
end

@gen function evaluate_function(func::Node, n_to_predict::Integer, xs::Vector{Float64}, ys::Vector{Float64}, init_angle::Float64, init_speed::Float64)
    func_state = init_func_state(n_to_predict, xs, ys, init_speed,  init_angle, true)
    node = Node("continue", "root", 1, [], [func])
    func_state = eval_node(node, func_state)
    return (func_state.output_x, func_state.output_y)  
end

function reload_state(state_path)
    loaded_state = open(deserialize, state_path)
    for i=1:length(loaded_state.traces)
        loaded_trace = loaded_state.traces[i]
        regenerated_trace, = generate(get_gen_fn(loaded_trace), get_args(loaded_trace), get_choices(loaded_trace))
        loaded_state.traces[i] = regenerated_trace
    end
    return loaded_state
end

function run_inference(xs::Vector{Float64}, ys::Vector{Float64}, n_particles::Integer, n_mcmc::Integer;
                seq_id="sequence", out_dir="output/", move_from_true=false, visualize=false, load_state=true, record_preds=false)
    
    n_points_observed = 2
    n_back = n_points_observed-1
    
    # Initialize visualization
    fig=""
    if visualize
        fig = visualize_init(xs,ys)
    end

    state_path = out_dir * "saved_states/" * seq_id * ".jls"
    prediction_path = out_dir * seq_id * ".csv"
    score_path = out_dir * seq_id * "_scores.csv"

    # Create dicts for storing predictions and scores
    prediction_dict = init_pred_dict(xs, ys, seq_id, n_particles)
    score_dict = Dict("score"=>[], "particle"=>[], "iter"=>[], "tpt"=>[], "a1"=>[], "a2"=>[], "a3"=>[], "a4"=>[], "a5"=>[])
    # Initialize particles with no observations
    observation = choicemap()
    traces = [generate(model, (xs[1:2], ys[1:2]), observation)[1] for _=1:n_particles]
    # Record t1 predictions
    record_predictions(prediction_dict, score_dict, traces, 1, xs, ys, seq_id, move_from_true, prediction_path, state_path, score_path, record_preds, n_back)
    
    init_t = 2
    for t=init_t:(length(xs)-2)
        println("Running tpt $t")
        vis_args = (t, xs, ys, fig, move_from_true, n_back)

        observation = choicemap()
        for i=1:n_back
            observation[:x=>i=>:v] = xs[t+1 - n_back + i] 
            observation[:y=>i=>:v] = ys[t+1 - n_back + i] 
        end

        traces = [generate(model, (xs[t-(n_back-1):t+1], ys[t-(n_back-1):t+1]), observation)[1] for _=1:n_particles] 

        # Apply MCMC rejuvenation to each particle
        @Threads.threads for i=1:n_particles 
            println("Particle $i")
            local trace = traces[i]
            trace, scores, acceptances = mcmc_rejuvenation(trace, n_mcmc, vis_args, visualize)
            traces[i] = trace
        end
        # Make predictions for tpt t+1 based on each particle
        record_predictions(prediction_dict, score_dict, traces, t, xs, ys, seq_id, move_from_true, prediction_path, state_path, score_path, record_preds, n_back)
    end

    # Return dicts holding sampled traces, predictions, and scores
    return (prediction_dict, score_dict)
end


function mcmc_rejuvenation(trace::Trace, n_mcmc::Int64, vis_args::Tuple{Int64, Vector{Float64}, Vector{Float64}, Any, Bool, Int64}, vis::Bool)
    scores = []
    acceptances = [Vector{Float64}(), Vector{Float64}(), Vector{Float64}(), Vector{Float64}(), Vector{Float64}()]
    for iter=1:n_mcmc
        trace, = mh(trace, Gen.select(:shape_x, :scale_x))
        trace, = mh(trace, Gen.select(:shape_y, :scale_y))
        trace, = mh(trace, init_angle_proposal, ())
        trace, = mh(trace, init_speed_proposal, ())
        trace, = mh(trace, Gen.select(:init_angle, :init_speed))
        trace, = mh(trace, Gen.select(:init_angle, :init_speed, :shape_x, :scale_x))
        trace, = mh(trace, Gen.select(:init_angle, :init_speed, :shape_y, :scale_y))
        if vis && (iter%10000)==0
            visualize_curr(vis_args, trace)
        end
    end
    return (trace, scores, acceptances)
end

function visualize_curr(vis_args, trace)
    (t, xs, ys, fig, move_from_true, n_back) = vis_args
    func = get_retval(trace)

    n_to_predict = n_back+1
    xs_model, ys_model = evaluate_function(func, n_to_predict, xs[t-(n_back-1):t+1], ys[t-(n_back-1):t+1], trace[:init_angle], trace[:init_speed])
    fig = ""
    fig = visualize_init(xs,ys)
    gui(scatter!(fig, xs_model, ys_model, c="blue", label=nothing))
    gui(scatter!(fig, xs[t-(n_back-1):t+1], ys[t-(n_back-1):t+1], c="red", label=nothing))
    
    println(func)
    println(trace[:init_angle])
    println(trace[:init_speed])
    println("------------")
end
 

function record_predictions(prediction_dict, score_dict, traces, t, xs, ys, seq_id, move_from_true,  prediction_path, state_path, score_path, record_preds, n_back)
    for (i, trace) in enumerate(traces)
        func = get_retval(trace)
        if t<n_back
            n_to_predict = t+1
            xs_model, ys_model = evaluate_function(func, n_to_predict, xs[1:t+1], ys[1:t+1], trace[:init_angle], trace[:init_speed])
        else
            n_to_predict = n_back+1
            xs_model, ys_model = evaluate_function(func, n_to_predict, xs[t-(n_back-1):t+1], ys[t-(n_back-1):t+1], trace[:init_angle], trace[:init_speed])
        end 
        push!(prediction_dict["particle"], i)
        push!(prediction_dict["tpt"], t+1)
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["func"], func)
        push!(prediction_dict["changepoints"], [])
        push!(prediction_dict["init_angle"], trace[:init_angle])
        push!(prediction_dict["init_speed"], trace[:init_speed])
        push!(prediction_dict["true_x"], xs[t+2])
        push!(prediction_dict["true_y"], ys[t+2])
        push!(prediction_dict["pred_x"], xs_model[end])
        push!(prediction_dict["pred_y"], ys_model[end])
        push!(prediction_dict["shape_x"], trace[:shape_x])
        push!(prediction_dict["shape_y"], trace[:shape_y])
        push!(prediction_dict["scale_x"], trace[:scale_x])
        push!(prediction_dict["scale_y"], trace[:scale_y])
        push!(prediction_dict["score"], get_score(trace))
    end
    # Record predictions
    if record_preds
        df = DataFrame(prediction_dict)
        CSV.write(prediction_path, df)
        # Scores
        df = DataFrame(score_dict)
        CSV.write(score_path, df)
    end
end

function init_pred_dict(xs, ys, seq_id, n_particles)
    prediction_dict = Dict("tpt"=> [], "particle"=> [], "true_x"=> [], "true_y"=> [], "pred_x"=> [], "pred_y"=>[], "seq_id"=>[], "func"=>[], "changepoints"=>[],  "shape_x"=>[], "shape_y"=>[], "scale_x"=>[], "scale_y"=>[], "init_angle"=>[], "init_speed"=>[], "score"=>[])
    for i=1:n_particles
        push!(prediction_dict["particle"], i)
        push!(prediction_dict["tpt"], 0)
        push!(prediction_dict["true_x"], xs[1])
        push!(prediction_dict["true_y"], ys[1])
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["func"], missing)
        push!(prediction_dict["changepoints"], missing)
        push!(prediction_dict["shape_x"], missing)
        push!(prediction_dict["shape_y"], missing)
        push!(prediction_dict["scale_x"], missing)
        push!(prediction_dict["scale_y"], missing)
        push!(prediction_dict["init_angle"], missing)
        push!(prediction_dict["init_speed"], missing)
        push!(prediction_dict["score"], missing)
        push!(prediction_dict["pred_x"], missing)
        push!(prediction_dict["pred_y"], missing)
    end
    for i=1:n_particles
        push!(prediction_dict["particle"], i)
        push!(prediction_dict["tpt"], 1)
        push!(prediction_dict["true_x"], xs[2])
        push!(prediction_dict["true_y"], ys[2])
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["func"], missing)
        push!(prediction_dict["changepoints"], missing)
        push!(prediction_dict["shape_x"], missing)
        push!(prediction_dict["shape_y"], missing)
        push!(prediction_dict["scale_x"], missing)
        push!(prediction_dict["scale_y"], missing)
        push!(prediction_dict["init_angle"], missing)
        push!(prediction_dict["init_speed"], missing)
        push!(prediction_dict["score"], missing)
        push!(prediction_dict["pred_x"], missing)
        push!(prediction_dict["pred_y"], missing)
    end
    return prediction_dict
end
