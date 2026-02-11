using CSV
using DataFrames
using JSON
using Profile

include("main.jl")

function scale_output(points)
    # Scale between -1 and 1
    min_point = minimum(points)
    max_point = maximum(points)
    if max_point == min_point
        return [0. for _ in points]
    else
    	scaled_points = [-1 + 2 * (point - min_point) / (max_point - min_point) for point in points]
    	return scaled_points
    end
end

function scale_input(points)
    # Scale between 0 and 1
    min_point = minimum(points)
    max_point = maximum(points)
    if max_point == min_point
        return [0. for _ in points]
    else
    	scaled_points = [(point - min_point) / (max_point - min_point) for point in points]
    	return scaled_points
    end
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
ts = collect(1:(length(xs)-1))

# Scale input data
prev_xs = Vector{Float64}(xs[1:end-1])
prev_ys = Vector{Float64}(ys[1:end-1])
prev_xs = scale_input(prev_xs)
prev_ys = scale_input(prev_ys)
ts = scale_input(ts)
input = [ts, prev_xs, prev_ys]
# Scale output data
out_x = xs[2:end]
out_y = ys[2:end]
out_x = scale_output(out_x)
out_y = scale_output(out_y)

# Run SMC
trace_dict = experiment_smc(input, out_x, out_y, seq_name, n_particles, n_iter, out_dir * seq_name * ".csv"; changepoints=false)
df = DataFrame(trace_dict)
CSV.write(out_dir * seq_name * ".csv", df)

