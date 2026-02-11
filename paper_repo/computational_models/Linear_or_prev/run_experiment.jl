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

out_dir = "output/"
mkpath(out_dir)
n_iter = parse(Int64, ARGS[3])
n_particles = parse(Int64, ARGS[4])

stim_path = ARGS[1]
seq_dict = JSON.parsefile(stim_path)["funcs"]
seq_names = collect(eachindex(seq_dict))
seq_idx = parse(Int64, ARGS[2])
seq_name = seq_names[seq_idx]
seq_info = seq_dict[seq_name]

xs = Vector{Float64}(seq_info["true_coords"][1])
ys = Vector{Float64}(seq_info["true_coords"][2])
xs, ys = scale_pts(xs, ys)
trace_dict = run_smc(xs, ys, n_particles, n_iter, seq_id=seq_name, out_dir=out_dir, move_from_true=true, visualize=false, load_state=true, record_preds=true)

