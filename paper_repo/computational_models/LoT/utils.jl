using Plots
using Gen
using Distributions 
using MutableNamedTuples
 
function init_func_state(n::Int, xs::Vector{Float64}, ys::Vector{Float64}, init_speed::Float64, init_angle::Float64, move_from_true::Bool)
    return MutableNamedTuple(true_xs=xs, true_ys=ys, x=xs[1], y=ys[1], num_to_generate=n, angle=init_angle, speed=init_speed, output_x=Vector{Float64}(), output_y=Vector{Float64}(), num_dots_generated=0, c=1, continue_count=0, move_from_true=move_from_true, env=Vector{Union{Float64, Int64}}())
end

function normalize(dist::Vector{Float64})
    return dist/sum(dist)
end

function sample_categorical(probs::Vector{Float64})
    u = rand()
    cdf = cumsum(probs)
    for (i, c) in enumerate(cdf)
        if u < c return i end
    end
end

function standardize(xs::Vector{Float64}, ys::Vector{Float64})
    # Compute centroid
    centroid_x = mean(xs)
    centroid_y = mean(ys)
    # Compute mean squared dist from centroid
    mse = mean([(xs[i] - centroid_x)^2 + (ys[i] - centroid_y)^2 for i=1:length(xs)])
    # Scaling factor = sqrt of mean squared dist bt each pt and centroid
    scale = mse^0.5
    if scale==0
        scale=1.0
    end
    # Subtract pt from centroid, then divide by sd
    std_xs = [(x - centroid_x)/scale for x in xs]
    std_ys = [(y - centroid_y)/scale for y in ys]
    return std_xs, std_ys, centroid_x, centroid_y, scale
end

function dict_to_dist(prob_dict::Dict, all_nodes::Vector{String})
    # Turn a dict of number, probability pairs into a normalized categorical distribution
    dist = Vector{Float64}()
    nodes_in_dict = collect(keys(prob_dict))
    for node_type in all_nodes
        if node_type in nodes_in_dict
            p = prob_dict[node_type]
        else
            p = 0
        end
        append!(dist, p)
    end
    dist = normalize(dist)
    return dist
end

function render_trace(trace; show_data=true)
    # Pull out xs from the trace
    xs, = get_args(trace)
    xmin = minimum(xs)
    xmax = maximum(xs)
    # Pull out the return value, useful for plotting
    func = get_retval(trace)
    fig = plot()
    if show_data
        xs = [trace[(:x, i)] for i=1:length(xs)]
        xs_model = evaluate_function(func, xs[1], 1., length(xs))
        println(func)
        println(xs)
        println(xs_model)
        scatter!(1:length(xs), xs_model, c="black", label=nothing)
    end
    return fig
end;

function grid(renderer::Function, traces)
    Plots.plot(map(renderer, traces)...)
end;

function round_all(xs::Vector{Float64}; n=2)
    map(x -> round(x; digits=n), xs)
end

function perm_visualize(pred_xs::Vector{Float64}, pred_ys::Vector{Float64}, fig, c="red")
    gui(scatter!(fig, pred_xs, pred_ys, c=c, label=nothing))
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


function node2str(node)
    str = string(node.tp) * "("
    n_children = length(node.children)
    for i=1:n_children
        str = str * node2str(node.children[i])
        if i != n_children
            str = str * ", "
        end
    end
    n_params = length(node.params)
    for i=1:n_params
        str = str * string(node.params[i])
        if i != n_params
            str = str * ", "
        end
    end
    str = str * ")"
    return str
end


function str2node(str, parent_tp="", parent_c=-1)
    idx =  findfirst("(", str)[1]
    tp = str[1:idx-1]
    rest = str[idx+1:end-1]

    child_list = Vector{Node}()
    if rest == "" 
        # No children or params
        return Node(tp, parent_tp, parent_c, [], child_list)
    elseif !(occursin("(",rest))
        # No children, only params
        if tp=="real"
            return Node(tp, parent_tp, parent_c, [parse(Float64, rest)], child_list)
        elseif tp=="int"
            return Node(tp, parent_tp, parent_c, [parse(Int64, rest)], child_list)
        else
            @assert false
        end
    else
        # Children
        child_ct = 1
        while length(rest) > 0
            node_end = get_node_end(rest)
            child_str = rest[1:node_end]
            if (child_str != "") & !isnothing(child_str)
                push!(child_list, str2node(child_str, tp, child_ct))
            end
            child_ct = child_ct + 1
            rest = rest[node_end+3:end]
        end
        return Node(tp, parent_tp, parent_c, [], child_list)
    end
end

function get_node_end(str)
    open_ct = 0
    close_ct = 0
    for (i,ch) in enumerate(str)
        ch = string(ch)
        if cmp(ch, "(")==0
            open_ct += 1
        end
        if cmp(ch, ")")==0
            close_ct += 1
        end
        if open_ct > 0 && open_ct==close_ct
            return i
        end
    end
end

function rotate_and_scale(pred_xs::Vector{Float64}, pred_ys::Vector{Float64}, true_xs::Vector{Float64}, true_ys::Vector{Float64})
    t = minimum([length(true_xs)-1, length(pred_xs)])
    if t<1
        return pred_xs, pred_ys
    end
    true_first = [true_xs[1], true_ys[1]]
    pred_first = [true_xs[1], true_ys[1]]
    true_last = [true_xs[t+1], true_ys[t+1]]
    pred_last = [pred_xs[t], pred_ys[t]]

    # Calculate scaling factor
    scale_factor = norm(true_last - true_first) / norm(pred_last - pred_first)
    
    # Calculate angle of rotation
    angle_true = atan(true_last[2] - true_first[2], true_last[1] - true_first[1])
    angle_pred = atan(pred_last[2] - pred_first[2], pred_last[1] - pred_first[1])
    rotation_angle = angle_true - angle_pred
    
    # Apply translation, scaling, and rotation to coordinates in list "a"
    transformed_xs = Vector{Float64}()
    transformed_ys = Vector{Float64}()
    for i=1:length(pred_xs)
        x_scaled = pred_xs[i] * scale_factor
        y_scaled = pred_ys[i] * scale_factor
        
        x_rotated = x_scaled * cos(rotation_angle) - y_scaled * sin(rotation_angle)
        y_rotated = x_scaled * sin(rotation_angle) + y_scaled * cos(rotation_angle)
        
        push!(transformed_xs, x_rotated)
        push!(transformed_ys, y_rotated)
    end
    
    return transformed_xs, transformed_ys
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

function choice_tup_to_trace(choice_tup, model, args)
    choices = unpack_choices_recursive(choice_tup)
    trace, score = generate(model, args, choices)
end
function unpack_choices_recursive(choice_tup)
    choices = choicemap()
    for (k, v) in choice_tup
        if isa(v, AbstractVector)
            set_submap!(choices, k, unpack_choices_recursive(v))
        else
            choices[k] = v
        end
    end
    return choices
end
