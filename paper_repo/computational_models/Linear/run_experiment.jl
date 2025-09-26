include("main.jl")
using CSV
using Distributions
using DataFrames
using JSON
using Profile

function scale_pts(xs, ys)
    distances = [sqrt((xs[i+1] - xs[i])^2 + (ys[i+1] - ys[i])^2) for i in 1:length(xs)-1]
    mean_dist = mean(distances)
    xs = [xs[i]/mean_dist for i=1:length(xs)]
    ys = [ys[i]/mean_dist for i=1:length(xs)]
    return xs, ys
end

n_iter = 100000
n_particles = 20
out_dir = "output/"
vis=false
load_state=true
record_preds=true

seq_dict = JSON.parsefile("stimuli.json")["funcs"]
seq_names = collect(eachindex(seq_dict))
seq_idx = parse(Int64, ARGS[1])
seq_name = seq_names[seq_idx]
println(seq_name)
seq_info = seq_dict[seq_name]

xs = Vector{Float64}(seq_info["true_coords"][1])
ys = Vector{Float64}(seq_info["true_coords"][2])
xs, ys = scale_pts(xs, ys)

# SMC Experiment
trace_dict, score_dict = run_inference(xs, ys, n_particles, n_iter, seq_id=seq_name, out_dir=out_dir, move_from_true=false, visualize=vis, load_state=load_state, record_preds=record_preds)
df = DataFrame(trace_dict)
CSV.write(out_dir * seq_name * ".csv", df)

