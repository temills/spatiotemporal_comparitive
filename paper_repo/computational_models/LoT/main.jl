include("grammar.jl")
include("utils.jl")
include("proposals.jl")
include("tDistribution.jl")

using CSV
using DataFrames
using Plots
using LinearAlgebra
using Serialization


"""
Main script for running inference over LoT programs
"""


""" Define priors """
@gen function pcfg_prior(type_dist::String, parent_tp::String, parent_c::Int64, env::Vector{String})
    # PCFG with bound variables
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
    if node_type in ["apply_expr_to_op_func", "map_list_to_op_func"]
        # sample arg before adding new bv to env
        c2 = @trace(pcfg_prior(child_types[2], node_type, 2, new_env), :c2)
        # then sample function
        bv_type = "expr"
        push!(new_env, bv_type)
        c1 = @trace(pcfg_prior(child_types[1], node_type, 1, new_env), :c1)

        push!(children, c1)
        push!(children, c2)
    else
        if length(child_types) > 0
            c1 = @trace(pcfg_prior(child_types[1], node_type, 1, new_env), :c1)
            push!(children, c1)
        end
        if length(child_types) > 1
            c2 = @trace(pcfg_prior(child_types[2], node_type, 2, new_env), :c2)
            push!(children, c2)
        end
    end
    node = Node(node_type, parent_tp, parent_c, params, children)

    return node
end
@dist number_prior_dist() = normal(0, 3)
@dist function int_prior_dist()
    d = Vector{Float64}()
    for i in 1:20
        append!(d, 1-(i*.04))
    end
    d = normalize(d)
    categorical(d)
end

@gen function sample_student_t(μ, α, β, n)
    ν = 2 * α
    σ = sqrt(1 / (β * n)) 
    v ~ student_t(μ, σ, ν)
end

@gen (static) function model(n::Integer, xs::Vector{Float64}, ys::Vector{Float64}, move_from_true::Bool, shape_params::Tuple{Float64, Float64}, scale_params::Tuple{Float64, Float64})
    # Generative model, returns a function
    func::Node = @trace(pcfg_prior("op", "root", 1, Vector{String}()), :tree)
    init_angle ~ uniform(-4, 4)
    init_speed ~ exponential(0.5)
    
    out_x, out_y = evaluate_function(func, n, xs, ys, init_speed, init_angle, move_from_true)

    # Marginalize over noise
    α_x = @trace(gamma(shape_params[1], shape_params[2]), :shape_x)
    β_x = @trace(gamma(scale_params[1], scale_params[2]), :scale_x)
    α_y = @trace(gamma(shape_params[1], shape_params[2]), :shape_y)
    β_y = @trace(gamma(scale_params[1], scale_params[2]), :scale_y)
    @trace(Map(sample_student_t)(out_x[1:n], fill(α_x, n), fill(β_x, n), fill(n, n)), :x)
    @trace(Map(sample_student_t)(out_y[1:n], fill(α_y, n), fill(β_y, n), fill(n, n)), :y)

    return func
end


@gen function evaluate_function(func::Node, n_to_predict::Integer, xs::Vector{Float64},
                            ys::Vector{Float64}, init_speed::Float64, init_angle::Float64, move_from_true::Bool)
    func_state = init_func_state(n_to_predict, xs, ys, abs(init_speed), init_angle, move_from_true)
    max_func_size = 40
    if func.size < max_func_size
        try
            n_inc = Node("increment_counter", "concat", 2, [], Vector{Node}())
            n_conc = Vector{Node}([Node("concat", "continue", 1, [], Vector{Node}([func, n_inc]))])
            node = Node("continue", "root", 1, [], n_conc)
            func_state = eval_node(node, func_state)
        catch err
            println(func)
            println(err)
        end
    end 
    if length(func_state.output_x) < n_to_predict
        func_state.output_x = fill(xs[1], n_to_predict)
        func_state.output_y = fill(ys[1], n_to_predict)
    end
    return func_state.output_x[1:n_to_predict], func_state.output_y[1:n_to_predict]
end

function reconstruct_trace(t, xs, ys, choices)
    constraints = choices
    trace, = generate(model, (t, xs[1:t+1], ys[1:t+1], true), constraints)
    return trace
end
function re_init_particle_filter(df, num_particles, xs, ys, choices)
    df = filter(row -> row.tpt == maximum(df.tpt), df)
    @assert nrow(df) == num_particles
    traces = Vector{U}(undef, num_particles)
    log_weights = Vector{U}(undef, num_particles)
    parents = Vector{U}(undef, num_particles)
    new_traces = Vector{U}(undef, num_particles)

    for row_idx=1:nrows(df)
        row = df[row_idx, :]
        particle = row.particle
        # Reconstruct trace
        traces[particle] = reconstruct_trace(row)
        log_weights[particle] = row.particle_weight
        parents[particle] = row.particle_parent
        log_ml_est = row.particle_ml_est
    end

    state = ParticleFilterState{U}(traces, new_traces, log_weights, log_ml_est, parents)
    return state
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

function run_smc(xs::Vector{Float64}, ys::Vector{Float64}, n_particles::Integer, n_mcmc::Integer;
                seq_id="sequence", out_dir="output/", move_from_true=true, visualize=false, load_state=false, record_preds=true)
    """
    Run SMC with MCMC rejuvenation
    """

    fig=""
    if visualize
        fig = visualize_init(xs,ys)
    end

    shape_params = (10., 10.)
    scale_params = (10., 10.)

    state_path = out_dir * "saved_states/" * seq_id * ".jls"
    prediction_path = out_dir * seq_id * ".csv"
    score_path = out_dir * seq_id * "_scores.csv"

    # Reload prediction dict and stored state if they exist, otherwise initialize
    if load_state && isfile(state_path) && isfile(prediction_path)
        state = reload_state(state_path)
        prediction_dict = Dict{String, Vector{Any}}()
        df = DataFrame(CSV.File(prediction_path))
        for col in names(df)
            prediction_dict[col] = collect(df[!, col])
        end
        if isfile(score_path)
            score_dict = Dict(pairs(eachcol(DataFrame(CSV.File(score_path)))))
        else
            score_dict = Dict("score"=>[],"particle"=>[],"iter"=>[],"tpt"=>[], "a1"=>[], "a2"=>[], "a3"=>[], "a4"=>[], "a5"=>[])
        end
        init_t = get_args(state.traces[1])[1] + 1
    else
        # Create dicts for storing predictions and scores
        prediction_dict = init_pred_dict(xs, ys, seq_id, n_particles)
        score_dict = Dict("score"=>[], "particle"=>[], "iter"=>[], "tpt"=>[], "a1"=>[], "a2"=>[], "a3"=>[], "a4"=>[], "a5"=>[])
        # Initialize particles with no observations
        observation = choicemap()
        state = initialize_particle_filter(
                    model,
                    (0, xs[1:1], ys[1:1], move_from_true, shape_params, scale_params),
                    observation, n_particles)
        # Record t0 predictions
        record_predictions(prediction_dict, score_dict, state, 0, xs, ys, seq_id, move_from_true, prediction_path, state_path, score_path)
        init_t = 1
    end


    # Run SMC
    for t=init_t:(length(xs)-2)
        println("Running SMC tpt $t")
        vis_args = (t+1, xs[1:t+2], ys[1:t+2], fig, move_from_true)

        # Observe data at tpt t, make prediction for tpt t+1
        observation = choicemap()
        observation[:x=>t=>:v] = xs[t+1]
        observation[:y=>t=>:v] = ys[t+1]
        # Run particle filter step on new observation, update weights
        Gen.particle_filter_step!(
                state,
                (t, xs[1:t+1], ys[1:t+1], move_from_true, shape_params, scale_params),
                (UnknownChange(), UnknownChange(), UnknownChange(), UnknownChange(), UnknownChange(), UnknownChange()),
                observation)
        
        # Apply MCMC rejuvenation to each particle
        predictions = Vector(undef, n_particles)
        @Threads.threads for i=1:n_particles 
            println("Particle $i")
            local trace = state.traces[i]
            trace, preds, scores, acceptances = mcmc_rejuvenation(trace, n_mcmc, vis_args, visualize, i, t, xs, ys, seq_id, move_from_true)
            predictions[i] = preds
            state.traces[i] = trace
        end

        for preds in predictions
            df = DataFrame(preds)
            CSV.write(prediction_path, df, append=true)
        end

        open(state_path, "w") do io
            serialize(io, state)
        end
    end

    # Return dicts holding sampled traces, predictions, and scores
    return (prediction_dict, score_dict)
end


function mcmc_rejuvenation(trace::Trace, n_mcmc::Int64, vis_args::Tuple{Int64, Vector{Float64}, Vector{Float64}, Any, Bool}, vis::Bool, particle, t, xs, ys, seq_id, move_from_true)
    prediction_dict = Dict("tpt"=> [], "particle"=> [], "true_x"=> [], "true_y"=> [], "pred_x"=> [], "pred_y"=>[], "seq_id"=>[], "func"=>[],  "shape_x"=>[], "shape_y"=>[], "scale_x"=>[], "scale_y"=>[], "init_angle"=>[], "init_speed"=>[], "score"=>[], "sample"=>[], "args"=>[], "choices"=>[])
    scores = []
    acceptances = [Vector{Float64}(), Vector{Float64}(), Vector{Float64}(), Vector{Float64}(), Vector{Float64}()]
    propose_params = false
    for iter=1:n_mcmc
        # Proposals on tree structure:
        trace, = mh(trace, regen_random_subtree, (propose_params,), subtree_involution) 
        trace, a = mh(trace, add_or_remove_c1, (propose_params,), add_or_remove_involution_c1)
        trace, = mh(trace, add_or_remove_c2, (propose_params,),  add_or_remove_involution_c2)
        trace, = mh(trace, swap_node, (propose_params,), swap_node_involution)
        
        # Proposals on params
        addr_list = get_param_addr_list(trace[:tree], [:tree], Vector{Tuple{Vector{Symbol}, Union{Float64, Int64}}}())
        for _=1:5
            trace, = mh(trace, init_angle_proposal, ())
            trace, = mh(trace, init_speed_proposal, ())
            trace, = mh(trace, Gen.select(:init_angle, :init_speed))
            for tup in addr_list
                trace,  = mh(trace, number_proposal, tup)
            end
            trace, = mh(trace, Gen.select(:shape_x))
            trace, = mh(trace, Gen.select(:scale_x))
            trace, = mh(trace, Gen.select(:shape_y))
            trace, = mh(trace, Gen.select(:scale_y))
        end
        # Record predictions
        if (iter==n_mcmc)
            func = get_retval(trace)
            xs_model, ys_model = evaluate_function(func, t+1, xs[1:t+1], ys[1:t+1], trace[:init_speed], trace[:init_angle], move_from_true)   
            push!(prediction_dict["particle"], particle)
            push!(prediction_dict["sample"], iter)
            push!(prediction_dict["tpt"], t+1)
            push!(prediction_dict["seq_id"], seq_id)
            push!(prediction_dict["func"], node2str(func))
            push!(prediction_dict["init_angle"], trace[:init_angle])
            push!(prediction_dict["init_speed"], trace[:init_speed])
            push!(prediction_dict["true_x"], xs[t+2])
            push!(prediction_dict["true_y"], ys[t+2])
            push!(prediction_dict["pred_x"], xs_model[t+1])
            push!(prediction_dict["pred_y"], ys_model[t+1])
            push!(prediction_dict["shape_x"], trace[:shape_x])
            push!(prediction_dict["shape_y"], trace[:shape_y])
            push!(prediction_dict["scale_x"], trace[:scale_x])
            push!(prediction_dict["scale_y"], trace[:scale_y])
            push!(prediction_dict["score"], get_score(trace))
            push!(prediction_dict["args"], get_args(trace))
            push!(prediction_dict["choices"], trace_to_choice_tup(trace))
        end
        if vis && (iter%500)==0
            visualize_curr(vis_args, trace)
        end
    end
    return (trace, prediction_dict, scores, acceptances)
end

function visualize_curr(vis_args, trace)
    (t, xs, ys, fig, move_from_true) = vis_args
    func = get_retval(trace)
    xs_model, ys_model = evaluate_function(func, t, xs[1:end-1], ys[1:end-1], trace[:init_speed], trace[:init_angle], move_from_true)
    fig = ""
    fig = visualize_init(xs,ys)
    gui(scatter!(fig, xs_model, ys_model, c="blue", label=nothing))
    println(node2str(func))
    println(get_score(trace))
end

function record_predictions(prediction_dict, score_dict, state, t, xs, ys, seq_id, move_from_true, prediction_path, state_path, score_path)
    traces = state.traces
    for (i, trace) in enumerate(traces)
        func = get_retval(trace)
        xs_model, ys_model = evaluate_function(func, t+1, xs[1:t+1], ys[1:t+1], trace[:init_speed], trace[:init_angle], move_from_true)   
        push!(prediction_dict["particle"], i)
        push!(prediction_dict["sample"], missing)
        push!(prediction_dict["tpt"], t+1)
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["func"], node2str(func))
        push!(prediction_dict["init_angle"], trace[:init_angle])
        push!(prediction_dict["init_speed"], trace[:init_speed])
        push!(prediction_dict["true_x"], xs[t+2])
        push!(prediction_dict["true_y"], ys[t+2])
        push!(prediction_dict["pred_x"], xs_model[t+1])
        push!(prediction_dict["pred_y"], ys_model[t+1])
        push!(prediction_dict["shape_x"], trace[:shape_x])
        push!(prediction_dict["shape_y"], trace[:shape_y])
        push!(prediction_dict["scale_x"], trace[:scale_x])
        push!(prediction_dict["scale_y"], trace[:scale_y])
        push!(prediction_dict["score"], get_score(trace))
        push!(prediction_dict["args"], get_args(trace))
        push!(prediction_dict["choices"], trace_to_choice_tup(trace))
    end
    # Record predictions
    df = DataFrame(prediction_dict)
    CSV.write(prediction_path, df)
    # Save state
    open(state_path, "w") do io
        serialize(io, state)
    end
    # Save scores
    df = DataFrame(score_dict)
    CSV.write(score_path, df)
end

function init_pred_dict(xs, ys, seq_id, n_particles)
    prediction_dict = Dict("tpt"=> [], "particle"=> [], "true_x"=> [], "true_y"=> [], "pred_x"=> [], "pred_y"=>[], "seq_id"=>[], "func"=>[],  "shape_x"=>[], "shape_y"=>[], "scale_x"=>[], "scale_y"=>[], "init_angle"=>[], "init_speed"=>[], "score"=>[], "sample"=>[], "args"=>[], "choices"=>[])
    for i=1:n_particles
        push!(prediction_dict["particle"], i)
        push!(prediction_dict["tpt"], 0)
        push!(prediction_dict["sample"], 1)
        push!(prediction_dict["true_x"], xs[1])
        push!(prediction_dict["true_y"], ys[1])
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["func"], missing)
        push!(prediction_dict["shape_x"], missing)
        push!(prediction_dict["shape_y"], missing)
        push!(prediction_dict["scale_x"], missing)
        push!(prediction_dict["scale_y"], missing)
        push!(prediction_dict["init_angle"], missing)
        push!(prediction_dict["init_speed"], missing)
        push!(prediction_dict["score"], missing)
        push!(prediction_dict["pred_x"], missing)
        push!(prediction_dict["pred_y"], missing)
        push!(prediction_dict["args"], missing)
        push!(prediction_dict["choices"], missing)
    end
    return prediction_dict
end