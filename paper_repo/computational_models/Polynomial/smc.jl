include("main.jl")
include("utils.jl")
include("proposals.jl")
import LinearAlgebra
using CSV
using DataFrames
using Plots


# Custom implementation of particle_filter_step! in Gen
# that removes the error on !isempty(discard)
function Gen.particle_filter_step!(
        state::Gen.ParticleFilterState{U},
        new_args::Tuple,
        argdiffs::Tuple,
        observations::ChoiceMap) where {U}
    num_particles = length(state.traces)
    Threads.@threads for i=1:num_particles
        (state.new_traces[i], incr, _, discard) = update(
            state.traces[i], new_args, argdiffs, observations)
        state.log_weights[i] += incr
    end
    # swap references
    tmp = state.traces
    state.traces = state.new_traces
    state.new_traces = tmp
    return nothing
end


####### run SMC with MCMC rejuvenation. #######

function run_smc(
        xs::Vector{Float64},
        ys::Vector{Float64},
        ts_std::Vector{Float64},
        degree::Integer,
        n_particles::Integer,
        n_mcmc::Integer;
        seq_id="sequence",
        vis=false)

    # initialize particles with no observations
    terms = generate_polynomial_terms(degree, 3)

    observations = choicemap()

    t = 0
    xs_curr, ys_curr, ts_curr = xs[1:t+1], ys[1:t+1], ts_std[1:t+1]
    state = initialize_particle_filter(
                model,
                (terms,xs_curr,ys_curr, ts_curr),
                observations,
                n_particles)


    prediction_dict = Dict("tpt"=> [], "particle"=> [], "degree" => [], "weight"=> [], "weights_x"=>[], "weights_y"=>[], "terms"=>[], "true_x"=> [], "true_y"=> [], "pred_x"=> [], "pred_y"=> [], 
                    "sd_x"=> [], "sd_y"=> [], "seq_id"=>[], "score"=>[], "prev_x"=>[], "prev_y"=>[])

    for i=1:n_particles
        trace = state.traces[i]
        append!(prediction_dict["particle"], i)
        push!(prediction_dict["weight"], missing)
        push!(prediction_dict["degree"], degree)
        push!(prediction_dict["weights_x"], trace[:weights_x])
        push!(prediction_dict["weights_y"], trace[:weights_y])
        push!(prediction_dict["terms"], terms)
        append!(prediction_dict["tpt"], 0)
        append!(prediction_dict["true_x"], xs[1])
        append!(prediction_dict["true_y"], ys[1])
        push!(prediction_dict["seq_id"], seq_id)
        push!(prediction_dict["score"], missing)
        push!(prediction_dict["pred_x"], missing)
        push!(prediction_dict["pred_y"], missing)
        push!(prediction_dict["prev_x"], missing)
        push!(prediction_dict["prev_y"],missing)
        push!(prediction_dict["sd_x"], missing)
        push!(prediction_dict["sd_y"], missing)
    end

    extended_pred_dict = Dict("curr_tpt"=> [], "pred_tpt"=> [], "particle"=> [], "degree" => [], "weight"=> [], "weights_x"=>[], "weights_y"=>[], "terms"=>[], "true_x"=> [], "true_y"=> [], "pred_x"=> [], "pred_y"=> [], 
    "sd_x"=> [], "sd_y"=> [], "seq_id"=>[], "score"=>[], "prev_x"=>[], "prev_y"=>[])

    for t in 1:(length(xs)-1)

        Threads.@threads for i=1:n_particles
            local trace = state.traces[i]
            trace = run_mcmc(trace, terms,  xs_curr, ys_curr, ts_curr, n_mcmc, vis=vis)
            state.traces[i] = trace
        end

        for (i, trace) in enumerate(state.traces)

            xs_model, ys_model = evaluate_function(terms, trace[:weights_x], trace[:weights_y], xs_curr, ys_curr, ts_curr)

            println(t, " ")
            println(xs)
            println(xs_model)
            println("")
            append!(prediction_dict["particle"], i)
            push!(prediction_dict["weight"], state.log_weights[i])
            push!(prediction_dict["degree"], degree)
            push!(prediction_dict["weights_x"], trace[:weights_x])
            push!(prediction_dict["weights_y"], trace[:weights_y])
            push!(prediction_dict["terms"], terms)
            append!(prediction_dict["tpt"], t)
            append!(prediction_dict["true_x"], xs[t+1])
            append!(prediction_dict["true_y"], ys[t+1])
            push!(prediction_dict["seq_id"], seq_id)
            push!(prediction_dict["score"], get_score(trace))
            push!(prediction_dict["pred_x"], xs_model[t+1])
            push!(prediction_dict["pred_y"], ys_model[t+1])
            push!(prediction_dict["prev_x"], xs[t])
            push!(prediction_dict["prev_y"], ys[t])
            push!(prediction_dict["sd_x"], √(1/trace[:precision_x]))
            push!(prediction_dict["sd_y"], √(1/trace[:precision_y]))
        end

        for (i, trace) in enumerate(state.traces)
           xs_model, ys_model = evaluate_function_extended(terms, trace[:weights_x], trace[:weights_y], xs_curr, ys_curr, ts_std)
           for pred_tpt=1:15
                append!(extended_pred_dict["particle"], i)
                push!(extended_pred_dict["weight"], state.log_weights[i])
                push!(extended_pred_dict["weights_x"], trace[:weights_x])
                push!(extended_pred_dict["weights_y"], trace[:weights_y])
                push!(extended_pred_dict["terms"], terms)
                push!(extended_pred_dict["degree"], degree)
                append!(extended_pred_dict["curr_tpt"], t)
                append!(extended_pred_dict["pred_tpt"], pred_tpt)
                append!(extended_pred_dict["true_x"], xs[pred_tpt+1])
                append!(extended_pred_dict["true_y"], ys[pred_tpt+1])
                push!(extended_pred_dict["seq_id"], seq_id)
                push!(extended_pred_dict["score"], get_score(trace))
                push!(extended_pred_dict["pred_x"], xs_model[pred_tpt+1])
                push!(extended_pred_dict["pred_y"], ys_model[pred_tpt+1])
                push!(extended_pred_dict["prev_x"], xs[pred_tpt])
                push!(extended_pred_dict["prev_y"], ys[pred_tpt])
                push!(extended_pred_dict["sd_x"], √(1/trace[:precision_x]))
                push!(extended_pred_dict["sd_y"], √(1/trace[:precision_y]))
            end
        end

        xs_curr, ys_curr, ts_curr = xs[1:t+1], ys[1:t+1], ts_std[1:t+1]

        if t < length(xs)-1
            observation = choicemap()
            observation[(:x, t)] = xs[t+1]
            observation[(:y, t)] = ys[t+1]
            Gen.particle_filter_step!(
                state,
                (terms, xs_curr, ys_curr, ts_curr),
                (UnknownChange(), UnknownChange(), UnknownChange()),
                observation)
        end
    end
    return prediction_dict

end
