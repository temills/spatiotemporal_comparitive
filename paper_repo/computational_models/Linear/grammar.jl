import Random
using Distributions
using Gen
include("utils.jl")

""" This file contains the node types and distributions over types which are used in proposals """

struct Node
    tp::String
    parent_tp::String
    parent_c::Int
    params::Vector{Any}
    children::Vector{Node}
    bv_idx::Int #specified for a function node
    size::Int
end
Base.size(node::Node) = node.size
Node(tp, parent_tp, parent_c, params, children::Vector{Node}) = Node(tp, parent_tp, parent_c, params, children, -1, sum([c.size for c in children]) + 1,)
Node(tp, parent_tp, parent_c, params, children::Vector{Node}, bv_idx::Int64) = Node(tp, parent_tp, parent_c, params, children, bv_idx, sum([c.size for c in children]) + 1,)

function eval_node(node::Node, func_state::MutableNamedTuple, n_recurse::Int64=0)
    n_recurse = n_recurse + 1
    if node.tp in ["real", "int"]
        @assert length(node.params)==1
        return node.params[1]
    elseif node.tp in ["move", "move_t", "move_s", "move_ts", "move_dts"]
        if node.tp == "move"
            θ = func_state.angle
            s = func_state.speed
        elseif node.tp == "move_t"
            θ = eval_node(node.children[1], func_state, n_recurse)
            s = func_state.speed
        elseif node.tp == "move_s"
            θ = func_state.angle
            s = eval_node(node.children[1], func_state, n_recurse)
        elseif node.tp == "move_ts"
            θ = eval_node(node.children[1], func_state, n_recurse)
            s = eval_node(node.children[2], func_state, n_recurse)
        elseif node.tp == "move_dts"
            θ = func_state.angle + eval_node(node.children[1], func_state, n_recurse)
            s = func_state.speed + eval_node(node.children[2], func_state, n_recurse)
        end
        func_state.x = func_state.x + (s * cos(θ * pi/2)) 
        func_state.y = func_state.y + (s * sin(θ * pi/2))
        push!(func_state.output_x, func_state.x)
        push!(func_state.output_y, func_state.y)
        func_state.num_dots_generated = func_state.num_dots_generated + 1
        if func_state.move_from_true && func_state.num_dots_generated < length(func_state.true_xs)
            func_state.x = func_state.true_xs[func_state.num_dots_generated+1]
            func_state.y = func_state.true_ys[func_state.num_dots_generated+1]
        end
        return func_state
    elseif node.tp in ["move_x", "move_y", "move_dxy", "move_xy"]
        if node.tp == "move_x"
            dx = eval_node(node.children[1], func_state, n_recurse)
            func_state.x = func_state.x + dx
            func_state.y = func_state.y + (func_state.speed * sin(func_state.angle * pi/2))
        elseif node.tp == "move_y"
            dy = eval_node(node.children[1], func_state, n_recurse)
            func_state.x = func_state.x + (func_state.speed * cos(func_state.angle * pi/2)) 
            func_state.y = func_state.y + dy
        elseif node.tp == "move_dxy"
            dx = eval_node(node.children[1], func_state, n_recurse)
            dy = eval_node(node.children[2], func_state, n_recurse)
            func_state.x = func_state.x + dx
            func_state.y = func_state.y + dy
        elseif node.tp == "move_xy"
            x = eval_node(node.children[1], func_state, n_recurse)
            y = eval_node(node.children[2], func_state, n_recurse)
            func_state.x = x
            func_state.y = y
        end
        push!(func_state.output_x, func_state.x)
        push!(func_state.output_y, func_state.y)
        func_state.num_dots_generated = func_state.num_dots_generated + 1
        if func_state.move_from_true && func_state.num_dots_generated < length(func_state.true_xs)
            func_state.x = func_state.true_xs[func_state.num_dots_generated+1]
            func_state.y = func_state.true_ys[func_state.num_dots_generated+1]
        end
        return func_state
    elseif node.tp == "continue"
        # Only allow for one "continue" per func
        if func_state.continue_count > 1
            return func_state
        end
        func_state.continue_count = func_state.continue_count + 1
        # Only loop up to n_predictions times
        count = 0
        while (length(func_state.output_x) < func_state.num_to_generate) && (count < func_state.num_to_generate)
            func_state = eval_node(node.children[1], func_state, n_recurse)#
            count = count + 1
        end
        return func_state
    else
        error("Unknown node type: $(node.tp)")
    end
end


function add_primitive(name::String, types, child_types)
    grammar[name] = Dict("types"=>types, "child_types"=>child_types)
    push!(node_list, name)
end
node_list = Vector{String}() # Holds primitive names, guaranteed types, and children's types
grammar = Dict()
add_primitive("real", ["expr"], [])
add_primitive("move", ["op"], [])


grammar["root"] = Dict("child_types"=>["op"])
function make_dist_dict()
    expr_dict = Dict()
    int_expr_dict = Dict()
    lambda_op_dict = Dict()
    lambda_expr_dict = Dict()
    op_dict = Dict()
    op_to_op_c1_dict = Dict()
    expr_to_expr_c1_dict = Dict()
    op_to_op_c2_dict = Dict()
    expr_to_expr_c2_dict = Dict()
    internal_var_dict = Dict()
    arithmetic_dict = Dict()
    move_dict = Dict()
    list_dict = Dict()
    for p in node_list
        p_dict = grammar[p]
        n_children = length(p_dict["child_types"])
        n_children_of_same_type = length([t for t in p_dict["child_types"] if t in p_dict["types"]])

        if "expr" in p_dict["types"]
            expr_dict[p] = 1 / 2^(n_children_of_same_type)
            if "int_expr" in p_dict["types"]
                int_expr_dict[p] = 1 / 2^(length([t for t in p_dict["child_types"] if t == "int_expr"]))
            end
            if n_children > 0
                if p_dict["child_types"][1] == "expr"
                    expr_to_expr_c1_dict[p] = 1 / 2^(n_children_of_same_type) 
                end
            end
            if n_children > 1
                if p_dict["child_types"][2] == "expr"
                    expr_to_expr_c2_dict[p] = 1 / 2^(n_children_of_same_type) 
                end
            end
        end
        if "op" in p_dict["types"]
            op_dict[p] = 1 / 2^(n_children_of_same_type)
            if n_children > 0
                if p_dict["child_types"][1] == "op"
                    op_to_op_c1_dict[p] = 1 / 2^(n_children_of_same_type) 
                end
            end
            if n_children > 1
                if p_dict["child_types"][2] == "op"
                    op_to_op_c2_dict[p] = 1 / 2^(n_children_of_same_type) 
                end
            end
        end
        if "lambda_op" in p_dict["types"]
            lambda_op_dict[p] = 1 / 2^(n_children_of_same_type)
        end
        if "lambda_expr" in p_dict["types"]
            lambda_expr_dict[p] = 1 / 2^(n_children_of_same_type)
        end
        if "list" in p_dict["types"]
            list_dict[p] = 1 / 2^(n_children_of_same_type)
        end
        if "internal_var" in p_dict["types"]
            internal_var_dict[p] = 1 / 2^(n_children_of_same_type)
        end
        if "arithmetic" in p_dict["types"]
            arithmetic_dict[p] = 1 / 2^(n_children_of_same_type)
        end
    end

    dist_dict = Dict(
        "expr" => dict_to_dist(expr_dict, node_list),
        "op" => dict_to_dist(op_dict, node_list),
        "internal_var"=>dict_to_dist(internal_var_dict, node_list),
        "arithmetic"=>dict_to_dist(arithmetic_dict, node_list),
        "op_to_op_c1" => dict_to_dist(op_to_op_c1_dict, node_list),
        "expr_to_expr_c1" => dict_to_dist(expr_to_expr_c1_dict, node_list),
        "op_to_op_c2" => dict_to_dist(op_to_op_c2_dict, node_list),
        "expr_to_expr_c2" => dict_to_dist(expr_to_expr_c2_dict, node_list),
        "int_expr" => dict_to_dist(int_expr_dict, node_list),
        "move"=>dict_to_dist(move_dict, node_list),
        "list"=>dict_to_dist(list_dict, node_list),
        "lambda_op"=>dict_to_dist(lambda_op_dict, node_list),
        "lambda_expr"=>dict_to_dist(lambda_expr_dict, node_list)
    )
    return dist_dict
end

dist_dict = make_dist_dict()

function get_node_types(tp)
    if tp[1:2]=="bv"
        return ["expr"]
    else
        return grammar[tp]["types"]
    end
end

function get_node_dist_swap(change_node)
    # Distribution over nodes that are an acceptable child of change_node's parent, 
    # and an acceptable parent of change_node's children
    prob_dict = Dict()
    for node_tp in node_list
        if length(grammar[node_tp]["child_types"])==length(grammar[change_node.tp]["child_types"])
            ok = true
            for (i,c) in enumerate(change_node.children)
                if ~(grammar[node_tp]["child_types"][i] in get_node_types(c.tp))
                    ok=false
                end
            end
            if ok && grammar[change_node.parent_tp]["child_types"][change_node.parent_c] in grammar[node_tp]["types"]
                prob_dict[node_tp] = 1
            end
        end
    end
    return dict_to_dist(prob_dict, node_list)
end

function get_node_dist_add_c1(change_node)
    # Distribution over nodes that are an acceptable parent of change_node (as c1)
    # and an acceptable child of change_node's parent
    prob_dict = Dict()
    for node_tp in node_list
        if length(grammar[node_tp]["child_types"])>0 && grammar[node_tp]["child_types"][1] in get_node_types(change_node.tp)
            if grammar[change_node.parent_tp]["child_types"][change_node.parent_c] in grammar[node_tp]["types"]
                prob_dict[node_tp] = 1
            end
        end
    end
    if length(values(prob_dict))==0
        return nothing
    else
        return dict_to_dist(prob_dict, node_list)
    end
end

function get_node_dist_add_c2(change_node)
    # Distribution over nodes that are an acceptable parent of change_node (as c2)
    # and an acceptable child of change_node's parent
    prob_dict = Dict()
    for node_tp in node_list
        if length(grammar[node_tp]["child_types"])>1 && grammar[node_tp]["child_types"][2] in get_node_types(change_node.tp)
            if grammar[change_node.parent_tp]["child_types"][change_node.parent_c] in grammar[node_tp]["types"]
                prob_dict[node_tp] = 1
            end
        end
    end
    if length(values(prob_dict))==0
        return nothing
    else
        return dict_to_dist(prob_dict, node_list)
    end
end



