using CSV
using DataFrames
using JSON
using Profile

include("smc.jl")

function scale_pts(xs, ys,ts)
    """ scale input between 0 and 1 """
    xs = [(xs[i]-mean(xs)) for i=1:length(xs)]
    ys = [(ys[i]-mean(ys)) for i=1:length(xs)]
    ts = [(ts[i]-mean(ts)) for i=1:length(xs)]
    if (minimum(xs) == maximum(xs))
        xs = [0. for i=1:length(xs)]
    else
        xs = xs/std(xs)
    end
    if (minimum(ys) == maximum(ys))
        ys = [0. for i=1:length(ys)]
    else
        ys = ys/std(ys)
    end
    if (minimum(ts) == maximum(ts))
        ts = [0. for i=1:length(ts)]
    else
        ts = ts/std(ts)
    end
    return xs, ys, ts
end

n_iter = 100000
n_particles = 20
degree = 1

seq_dict = JSON.parsefile("../stimuli.json")["funcs"]
seq_idx = parse(Int64, ARGS[1])
seq_name = collect(eachindex(seq_dict))[seq_idx]
seq_info = seq_dict[seq_name] 

outdir = "output/"

xs = Vector{Float64}(seq_info["true_coords"][1])
ys = Vector{Float64}(seq_info["true_coords"][2])
ts = collect(range(0,length(xs),step=1.0))

xs, ys, ts_std = scale_pts(xs, ys, ts)

# run SMC
trace_dict = run_smc(xs,ys,ts_std, degree, n_particles, n_iter, seq_id=seq_name, vis=false)
df = DataFrame(trace_dict)
CSV.write(outdir * seq_name * ".csv", df)

