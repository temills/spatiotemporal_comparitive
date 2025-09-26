using CSV
using DataFrames
using JSON

include("main.jl")

function scale_pts(xs, ys)
    distances = [sqrt((xs[i+1] - xs[i])^2 + (ys[i+1] - ys[i])^2) for i in 1:length(xs)-1]
    mean_dist = mean(distances)
    xs = xs./mean_dist
    ys = ys./mean_dist
    return xs, ys
end

n_iter = 100000
n_particles = 20

out_dir = "output/"

seq_dict = JSON.parsefile("../stimuli.json")["funcs"]
seq_names = collect(keys(seq_dict))
seq_idx = parse(Int64, ARGS[1])
seq_name = seq_names[seq_idx]

seq_info = seq_dict[seq_name]

xs = Vector{Float64}(seq_info["true_coords"][1])
ys = Vector{Float64}(seq_info["true_coords"][2])
xs, ys = scale_pts(xs, ys)
trace_dict = run_smc(xs, ys, n_particles, n_iter, seq_id=seq_name, out_dir=out_dir, move_from_true=true, visualize=false, load_state=true, record_preds=true)

