using Distributions
using Gen
using Plots

function get_previous_points(input_x::Vector{Float64}, input_y::Vector{Float64})
    """ Return previous point locations """
    max_dist = 0.001
    blocks = [[input_x[1], input_y[1]]]
    n = length(input_x)
    for i=2:n
        new_block = true
        for (j, b) in enumerate(blocks)
            if (abs(input_x[i]-b[1]) < max_dist) && (abs(input_y[i]-b[2]) < max_dist)
                new_block = false
                break
            end
        end
        if new_block
            push!(blocks, [input_x[i], input_y[i]])
        end
    end
    return [b[1] for b in blocks], [b[2] for b in blocks]
end

function vec_extrap(input_x::Vector{Float64}, input_y::Vector{Float64})
    """ Compute linear extrapolation based on previous two movements """
    if length(input_x)==1
        return [input_x[1], input_y[1]]
    else
        dx = input_x[2:end] .- input_x[1:end-1]
        dy = input_y[2:end] .- input_y[1:end-1]

        dx = dx[max(end-1, 1):end]
        dy = dy[max(end-1, 1):end]

        return [input_x[end] + mean(dx), input_y[end] + mean(dy)]
    end
end

mixture_of_normals = HomogeneousMixture(normal, [0, 0])

@gen function model(input_x::Vector{Float64}, input_y::Vector{Float64})
    p_periodic ~ beta(1,1)
    periodic_σ_x ~ exponential(3)
    vec_σ_x ~ exponential(3)
    periodic_σ_y ~ exponential(3)
    vec_σ_y ~ exponential(3)
    for n=1:length(input_x)-1
        # Generate next point by sampling previous point
        periodic_means_x, periodic_means_y = get_previous_points(input_x[1:n], input_y[1:n])
        # Generate next point through linear extrapolation
        vec_mean_x, vec_mean_y = vec_extrap(input_x[1:n], input_y[1:n])
        # Weight predictions in mixture
        weights = [fill((1/length(periodic_means_x))*p_periodic, length(periodic_means_x)); (1-p_periodic)]
        means_x = [periodic_means_x; vec_mean_x]
        means_y = [periodic_means_y; vec_mean_y]
        sds_x = [fill(periodic_σ_x, length(periodic_means_x)); vec_σ_x]
        sds_y = [fill(periodic_σ_y, length(periodic_means_x)); vec_σ_y]
        @trace(mixture_of_normals(weights, means_x, sds_x), (:obs_x, n))
        @trace(mixture_of_normals(weights, means_y, sds_y), (:obs_y, n))
    end
end

@gen function get_prediction(input_x::Vector{Float64}, input_y::Vector{Float64}, p_periodic, periodic_σ_x, periodic_σ_y,  vec_σ_x, vec_σ_y)
    # Generate next point by sampling previous point
    periodic_means_x, periodic_means_y = get_previous_points(input_x, input_y)
    # Generate next point through linear extrapolation
    vec_mean_x, vec_mean_y = vec_extrap(input_x, input_y)
    n = length(periodic_means_x)
    # Weight predictions in mixture
    weights = [fill((1/n)*p_periodic, n); (1-p_periodic)]
    means_x = [periodic_means_x; vec_mean_x]
    means_y = [periodic_means_y; vec_mean_y]
    sds_x = [fill(periodic_σ_x, n); vec_σ_x]
    sds_y = [fill(periodic_σ_y, n); vec_σ_y]
    # Sample prediction
    i = categorical(weights)
    return means_x, means_y, weights, sds_x, sds_y, means_x[i], means_y[i], sds_x[i], sds_y[i]
end

""" Run SMC with MCMC rejuvenation """
function run_smc(xs::Vector{Float64}, ys::Vector{Float64}, n_particles::Integer, n_mcmc::Integer;
                seq_id="sequence", out_dir="output/", move_from_true=true, visualize=false, load_state=true, record_preds=true)
    # Initialize visualization
    fig=""
    if visualize
        fig = visualize_init(xs,ys)
    end
    prediction_path = out_dir * seq_id * ".csv"
    prediction_dict = init_pred_dict(xs, ys, seq_id, n_particles)
    # Initialize particles with no observations
    observation = choicemap()
    state = initialize_particle_filter(
                model,
                (xs[1:1], ys[1:1]),
                observation, n_particles)
    record_predictions(prediction_dict, state, 0, xs, ys, seq_id, prediction_path)
    init_t = 1

    # Run SMC
    for t=init_t:(length(xs)-2)
        println("Running SMC tpt $t")
        vis_args = (t+1, xs[1:t+1], ys[1:t+1], fig)

        # Observe data at tpt t, make prediction for tpt t+1
        observation = choicemap()
        observation[(:obs_x, t)] = xs[t+1]
        observation[(:obs_y, t)] = ys[t+1]
        # Run particle filter step on new observation, update weights
        Gen.particle_filter_step!(
                state,
                (xs[1:t+1], ys[1:t+1]),
                (UnknownChange(), UnknownChange()),
                observation)
        
        # Apply MCMC rejuvenation to each particle
        predictions = Vector(undef, n_particles)
        for i=1:n_particles
            local trace = state.traces[i]
            trace, preds = @time mcmc_rejuvenation(trace, n_mcmc, vis_args, visualize, i, t, xs, ys, seq_id)
            predictions[i] = preds
            state.traces[i] = trace
        end
        for preds in predictions
            df = DataFrame(preds)
            CSV.write(prediction_path, df, append=true)
        end
    end
    # Return dicts holding sampled traces, predictions, and scores
    return prediction_dict
end


function mcmc_rejuvenation(trace::Trace, n_mcmc::Int64, vis_args::Tuple{Int64, Vector{Float64}, Vector{Float64}, Any}, vis::Bool, particle, t, xs, ys, seq_id)
    prediction_dict = Dict("tpt"=> [], "particle"=> [], "true_x"=> [], "true_y"=> [], "pred_x"=> [], "pred_y"=>[], "seq_id"=>[], "sd_periodic_x"=>[], "sd_periodic_y"=>[], "sd_vec_x"=>[], "sd_vec_y"=>[], "p_periodic"=>[], "means_x"=>[], "means_y"=>[], "weights"=>[], "score"=>[], "sample_sd_x"=>[], "sample_sd_y"=>[], "sample"=>[], "args"=>[], "choices"=>[])
    scores = []
    for iter=1:n_mcmc
        trace, = mh(trace, Gen.select(:periodic_σ)) 
        trace, = mh(trace, Gen.select(:vec_σ))
        trace, = mh(trace, Gen.select(:p_periodic)) 

        if (iter>1000)&&(iter%n_mcmc==0)
            means_x, means_y, weights, sds_x, sds_y, sample_x, sample_y, sample_sd_x, sample_sd_y = get_prediction(xs[1:t+1], ys[1:t+1], trace[:p_periodic], trace[:periodic_σ_x], trace[:periodic_σ_y], trace[:vec_σ_x], trace[:vec_σ_y])
            push!(prediction_dict["particle"], particle)
            push!(prediction_dict["sample"], iter)
            push!(prediction_dict["tpt"], t+1)
            push!(prediction_dict["seq_id"], seq_id)
            push!(prediction_dict["true_x"], xs[t+2])
            push!(prediction_dict["true_y"], ys[t+2])
            push!(prediction_dict["pred_x"], sample_x)
            push!(prediction_dict["pred_y"], sample_y)
            push!(prediction_dict["sample_sd_x"], sample_sd_x)
            push!(prediction_dict["sample_sd_y"], sample_sd_y)
            push!(prediction_dict["sd_periodic_x"], trace[:periodic_σ_x])
            push!(prediction_dict["sd_periodic_y"], trace[:periodic_σ_y])
            push!(prediction_dict["means_x"], means_x)
            push!(prediction_dict["means_y"], means_y)
            push!(prediction_dict["weights"], weights)
            push!(prediction_dict["sd_vec_x"], trace[:vec_σ_x])
            push!(prediction_dict["sd_vec_y"], trace[:vec_σ_y])
            push!(prediction_dict["p_periodic"], trace[:p_periodic])
            push!(prediction_dict["score"], get_score(trace))
            push!(prediction_dict["args"], get_args(trace))
            push!(prediction_dict["choices"], trace_to_choice_tup(trace))
        end
        if vis && (iter%10000)==0
            visualize_curr(vis_args, trace)
        end
    end
    return (trace, prediction_dict)
end

function visualize_init(xs,ys)
    Plots.CURRENT_PLOT.nullableplot = nothing
    xmin=minimum(xs)
    xmax=maximum(xs)
    x_diff = xmax-xmin+1
    ymin=minimum(ys)
    ymax=maximum(ys)
    y_diff = ymax-ymin+1
    fig = plot!(xs, ys, color="black", xlim=(xmin-x_diff,xmax+x_diff), ylim=(ymin-y_diff,ymax+y_diff))
    gui(fig)
    gui(scatter!(fig, xs, ys, c="black", label=nothing))
    return fig
end

function visualize_curr(vis_args, trace)
    (t, xs, ys, fig) = vis_args
    means_x, means_y, weights, sds_x, sds_y, sample_x, sample_y, sample_sd_x, sample_sd_y = get_prediction(xs, ys, trace[:p_periodic], trace[:periodic_σ_x], trace[:periodic_σ_y], trace[:vec_σ_x], trace[:vec_σ_y])
    fig = ""
    fig = visualize_init(xs,ys)
    gui(scatter!(fig, means_x, means_y, c="blue", alpha=weights, label=nothing))
    gui(scatter!(fig, [sample_x], [sample_y], c="gold", label=nothing))
    println(get_score(trace))
    println(xs)
    println(ys)
end

function record_predictions(prediction_dict, state, t, xs, ys, seq_id, prediction_path)
    traces = state.traces
    for (i, trace) in enumerate(traces)
        means_x, means_y, weights, sds_x, sds_y, sample_x, sample_y, sample_sd_x, sample_sd_y = get_prediction(xs[1:t+1], ys[1:t+1], trace[:p_periodic], trace[:periodic_σ_x], trace[:periodic_σ_y], trace[:vec_σ_x], trace[:vec_σ_y])
        push!(prediction_dict["particle"], i)
        push!(prediction_dict["sample"], 1)
        push!(prediction_dict["tpt"], t+1)
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["true_x"], xs[t+2])
        push!(prediction_dict["true_y"], ys[t+2])
        push!(prediction_dict["pred_x"], sample_x)
        push!(prediction_dict["pred_y"], sample_y)
        push!(prediction_dict["sample_sd_x"], sample_sd_x)
        push!(prediction_dict["sample_sd_y"], sample_sd_y)
        push!(prediction_dict["sd_periodic_x"], trace[:periodic_σ_x])
        push!(prediction_dict["sd_periodic_y"], trace[:periodic_σ_y])
        push!(prediction_dict["means_x"], means_x)
        push!(prediction_dict["means_y"], means_y)
        push!(prediction_dict["weights"], weights)
        push!(prediction_dict["sd_vec_x"], trace[:vec_σ_x])
        push!(prediction_dict["sd_vec_y"], trace[:vec_σ_y])
        push!(prediction_dict["p_periodic"], trace[:p_periodic])
        push!(prediction_dict["score"], get_score(trace))
        push!(prediction_dict["args"], get_args(trace))
        push!(prediction_dict["choices"], trace_to_choice_tup(trace))
    end
    df = DataFrame(prediction_dict)
    CSV.write(prediction_path, df)
end

function init_pred_dict(xs, ys, seq_id, n_particles)
    prediction_dict = Dict("tpt"=> [], "particle"=> [], "true_x"=> [], "true_y"=> [], "pred_x"=> [], "pred_y"=>[], "seq_id"=>[], "sd_periodic_x"=>[], "sd_periodic_y"=>[],  "sd_vec_x"=>[], "sd_vec_y"=>[], "p_periodic"=>[], "means_x"=>[], "means_y"=>[], "weights"=>[], "score"=>[], "sample"=>[],"sample_sd_x"=>[],"sample_sd_y"=>[],  "args"=>[], "choices"=>[])
    for i=1:n_particles
        push!(prediction_dict["particle"], i)
        push!(prediction_dict["tpt"], 0)
        push!(prediction_dict["sample"], 1)
        push!(prediction_dict["true_x"], xs[1])
        push!(prediction_dict["true_y"], ys[1])
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["means_y"], missing)
        push!(prediction_dict["means_x"], missing)
        push!(prediction_dict["weights"], missing)
        push!(prediction_dict["sd_vec_x"], missing)
        push!(prediction_dict["sd_vec_y"], missing)
        push!(prediction_dict["sample_sd_x"], missing)
        push!(prediction_dict["sample_sd_y"], missing)
        push!(prediction_dict["p_periodic"], missing)
        push!(prediction_dict["sd_periodic_x"], missing)
        push!(prediction_dict["sd_periodic_y"], missing)
        push!(prediction_dict["score"], missing)
        push!(prediction_dict["pred_x"], missing)
        push!(prediction_dict["pred_y"], missing)
        push!(prediction_dict["args"], missing)
        push!(prediction_dict["choices"], missing)
    end
    return prediction_dict
end

function trace_to_choice_tup(trace::Trace)
    return store_choices_recursive(get_choices(trace))
end

function store_choices_recursive(choices::ChoiceMap)
    pairs = []
    val_iter = get_values_shallow(choices)
    for (k, v) in val_iter
        push!(pairs, (k,v))
    end
    map_iter = get_submaps_shallow(choices)
    for (k, m) in map_iter
        push!(pairs, (k, store_choices_recursive(m)))
    end
    return pairs
end
