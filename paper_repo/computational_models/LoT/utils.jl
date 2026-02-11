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
