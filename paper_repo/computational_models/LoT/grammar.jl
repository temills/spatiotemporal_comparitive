import Random
using Gen
include("utils.jl")

################################
# This file contains the node types and distributions over types which are used in proposals
#    e.g. the `expr_to_expr_c1_dist' gives a categorical distribution over expr nodes whose first child is an expr node.
#    This is useful in add_node proposals,
#    when we might want to insert a node between an expr node and its first child which is an expr node
################################

USE_RECURSION = true

struct Node
    tp::String
    parent_tp::String
    parent_c::Int
    params::Vector{Any}
    children::Vector{Node}
    bv_idx::Int
    size::Int
end
Base.size(node::Node) = node.size
Node(tp, parent_tp, parent_c, params, children::Vector{Node}) = Node(tp, parent_tp, parent_c, params, children, -1, sum([c.size for c in children]) + 1,)
Node(tp, parent_tp, parent_c, params, children::Vector{Node}, bv_idx::Int64) = Node(tp, parent_tp, parent_c, params, children, bv_idx, sum([c.size for c in children]) + 1,)

function eval_node(node::Node, func_state::MutableNamedTuple, n_recurse::Int64=0)
    n_recurse = n_recurse + 1
    max_recurse = 100
    if n_recurse > max_recurse
        if "expr" in get_node_types(node.tp)
            return 0.
        elseif "op" in get_node_types(node.tp)
            return func_state
        end
    end
    if node.tp in ["real", "int"]
        @assert length(node.params)==1
        return node.params[1]
    elseif node.tp == "internal_var_type"
        return eval_node(node.children[1], func_state, n_recurse)
    elseif node.tp == "var_t"
        return func_state.num_dots_generated
    elseif node.tp == "var_c"
        return func_state.c
    elseif node.tp == "var_x"
        return func_state.x
    elseif node.tp == "var_y"
        return func_state.y
    elseif node.tp == "var_angle"
        return func_state.angle
    elseif node.tp == "var_speed"
        return func_state.speed
    elseif node.tp == "var_free"
        return func_state.var_free_value
    elseif node.tp == "round"
        return floor(eval_node(node.children[1], func_state, n_recurse))
    elseif node.tp == "arithmetic_type"
        return eval_node(node.children[1], func_state, n_recurse)
    elseif node.tp == "sin"
        return sin(eval_node(node.children[1], func_state, n_recurse))
    elseif node.tp == "plus"
        return eval_node(node.children[1], func_state, n_recurse) + eval_node(node.children[2], func_state, n_recurse)
    elseif node.tp == "minus"
        return eval_node(node.children[1], func_state, n_recurse) - eval_node(node.children[2], func_state, n_recurse)
    elseif node.tp == "negative"
        return -eval_node(node.children[1], func_state, n_recurse)
    elseif node.tp == "times"
        return eval_node(node.children[1], func_state, n_recurse) * eval_node(node.children[2], func_state, n_recurse)
    elseif node.tp == "divide"
        divisor = eval_node(node.children[2], func_state, n_recurse)
        if floor(divisor) == 0
            return 0
        else
            return eval_node(node.children[1], func_state, n_recurse) / divisor
        end
    elseif node.tp == "mod"
        divisor = eval_node(node.children[2], func_state, n_recurse)
        if floor(divisor) == 0
            return 0
        else
            return floor(eval_node(node.children[1], func_state, n_recurse)) % floor(divisor)
        end
    elseif node.tp == "change_x"
        dx = eval_node(node.children[1], func_state, n_recurse)
        func_state.x = func_state.x + dx
        return func_state
    elseif node.tp == "change_y"
        dy = eval_node(node.children[1], func_state, n_recurse)
        func_state.y = func_state.y + dy
        return func_state
    elseif node.tp == "set_x"
        x = eval_node(node.children[1], func_state, n_recurse)
        func_state.x = x
        return func_state
    elseif node.tp == "set_y"
        y = eval_node(node.children[1], func_state, n_recurse)
        func_state.y = y
        return func_state
    elseif node.tp == "change_angle"
        da = eval_node(node.children[1], func_state, n_recurse)
        func_state.angle = func_state.angle + da
        if func_state.angle >= 0
            func_state.angle = mod(func_state.angle, 4)
        else
            func_state.angle = mod(func_state.angle, -4)
        end
        return func_state
    elseif node.tp == "set_angle"
        a = eval_node(node.children[1], func_state, n_recurse)
        func_state.angle = a
        if func_state.angle >= 0
            func_state.angle = mod(func_state.angle, 4)
        else
            func_state.angle = mod(func_state.angle, -4)
        end
        return func_state
    elseif node.tp == "flip_angle"
        func_state.angle = -func_state.angle
        if func_state.angle >= 0
            func_state.angle = mod(func_state.angle, 4)
        else
            func_state.angle = mod(func_state.angle, -4)
        end
        return func_state
    elseif node.tp == "change_speed"
        ds = eval_node(node.children[1], func_state, n_recurse)
        func_state.speed = func_state.speed + ds
        return func_state
    elseif node.tp == "set_speed"
        s = eval_node(node.children[1], func_state, n_recurse)
        func_state.speed = s
        return func_state
    elseif node.tp in ["move", "move_t", "move_s", "move_ts", "move_dt"]
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
        elseif node.tp == "move_dt"
            θ = func_state.angle + eval_node(node.children[1], func_state, n_recurse)
            s = func_state.speed
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
    elseif node.tp in ["move_x", "move_y", "move_xy"]
        if node.tp == "move_x"
            dx = eval_node(node.children[1], func_state, n_recurse)
            func_state.x = func_state.x + dx
            func_state.y = func_state.y + (func_state.speed * sin(func_state.angle * pi/2))
        elseif node.tp == "move_y"
            dy = eval_node(node.children[1], func_state, n_recurse)
            func_state.x = func_state.x + (func_state.speed * cos(func_state.angle * pi/2)) 
            func_state.y = func_state.y + dy
        elseif node.tp == "move_xy"
            dx = eval_node(node.children[1], func_state, n_recurse)
            dy = eval_node(node.children[2], func_state, n_recurse)
            func_state.x = func_state.x + dx
            func_state.y = func_state.y + dy
        end
        push!(func_state.output_x, func_state.x)
        push!(func_state.output_y, func_state.y)
        func_state.num_dots_generated = func_state.num_dots_generated + 1
        if func_state.move_from_true && func_state.num_dots_generated < length(func_state.true_xs)
            func_state.x = func_state.true_xs[func_state.num_dots_generated+1]
            func_state.y = func_state.true_ys[func_state.num_dots_generated+1]
        end
        return func_state
    elseif node.tp == "dot"
        push!(func_state.output_x, func_state.x)
        push!(func_state.output_y, func_state.y)
        func_state.num_dots_generated = func_state.num_dots_generated + 1
        if func_state.move_from_true && func_state.num_dots_generated < length(func_state.true_xs)
            func_state.x = func_state.true_xs[func_state.num_dots_generated+1]
            func_state.y = func_state.true_ys[func_state.num_dots_generated+1]
        end
        return func_state
    elseif node.tp == "repeat"
        n = floor(eval_node(node.children[2], func_state, n_recurse))
        for i in 1:abs(n)
            if (i > func_state.num_to_generate) || (func_state.num_dots_generated > func_state.num_to_generate)
                break
            end
            func_state = eval_node(node.children[1], func_state)
        end
        return func_state
    elseif node.tp == "concat"
        func_state = eval_node(node.children[1], func_state, n_recurse)#
        func_state = eval_node(node.children[2], func_state, n_recurse)
        return func_state
    elseif node.tp == "subprogram"
        x, y, angle, speed = func_state.x, func_state.y, func_state.angle, func_state.speed
        func_state = eval_node(node.children[1], func_state, n_recurse)
        func_state.x, func_state.y, func_state.angle, func_state.speed = x, y, angle, speed
        return func_state
    elseif node.tp == "continue"
        # Only allow for one "continue" per func
        if func_state.continue_count > 1
            return func_state
        end
        func_state.continue_count = func_state.continue_count + 1
        # Only loop up to n_predictions time
        count = 0
        while (length(func_state.output_x) < func_state.num_to_generate) & (count < 1000)
            func_state = eval_node(node.children[1], func_state, n_recurse)#
            count = count + 1
        end
        return func_state
    elseif node.tp == "increment_counter"
        func_state.c = func_state.c + 1
        return func_state
    elseif node.tp[1:3] == "bv_" 
        bv_idx = parse(Int, node.tp[4:end])
        return func_state.env[bv_idx]
    elseif node.tp == "apply_expr_to_op_func"
        # child 1 is the op_func
        # child 2 is the argument
        arg = eval_node(node.children[2], func_state, n_recurse)
        # store value for the variable bound by this function
        push!(func_state.env, arg)
        f_body = node.children[1]
        func_state = eval_node(f_body, func_state, n_recurse)
        pop!(func_state.env)
        return func_state
    elseif node.tp == "apply_expr_to_expr_func"
        # child 1 is the expr_func
        # child 2 is the argument
        arg = eval_node(node.children[2], func_state, n_recurse)
        # store value for the variable bound by this function
        push!(func_state.env, arg)
        # eval function
        expr = eval_node(node.children[1], func_state,n_recurse) #after evaling, will remove var from env
        return expr
    elseif node.tp == "lambda_op"
        f_body = node.children[1]
        func_state = eval_node(f_body, func_state, n_recurse)
        pop!(func_state.env)
        return func_state
    elseif node.tp == "lambda_expr"
        f_body = node.children[1]
        expr = eval_node(f_body, func_state, n_recurse)
        pop!(func_state.env)
        return expr
    elseif node.tp == "map_list_to_op_func"
        arg_list = eval_node(node.children[2], func_state, n_recurse)
        for (i,arg) in enumerate(arg_list)
            if (i > func_state.num_to_generate) || (func_state.num_dots_generated > func_state.num_to_generate)
                break
            end
            push!(func_state.env, arg)
            f_body = node.children[1]
            func_state = eval_node(f_body, func_state, n_recurse)
            pop!(func_state.env)
        end
        return func_state
    elseif node.tp == "range"
        from = 1
        to = func_state.num_to_generate
        return collect(from:to)
    elseif node.tp == "range_by_x"
        by = eval_node(node.children[1], func_state, n_recurse)
        if by==0
            by=1
        end
        from = by
        to = func_state.num_to_generate * by
        return collect(from:by:to)
    elseif node.tp == "range_n_times"
        from = 1
        to = eval_node(node.children[1], func_state, n_recurse)
        return collect(from:to)
    elseif node.tp == "range_by_x_n_times"
        by = eval_node(node.children[1], func_state, n_recurse)
        if by==0
            by=1
        end
        from = by
        to = eval_node(node.children[2], func_state, n_recurse) * by
        return collect(from:by:to)
    else
        error("Unknown node type: $(node.tp)")
    end
end

function add_primitive(name::String, types, child_types)
    grammar[name] = Dict("types"=>types, "child_types"=>child_types)
    push!(node_list, name)
end
node_list = Vector{String}()
grammar = Dict()
grammar["root"] = Dict("child_types"=>["op"])

# base level expressions
add_primitive("real", ["expr"], [])
add_primitive("int", ["int_expr", "expr"], [])
# compositional expressions
add_primitive("plus", ["expr"], ["expr", "expr"])
add_primitive("minus", ["expr"], ["expr", "expr"])
add_primitive("times", ["expr"], ["expr", "expr"])
add_primitive("divide", ["expr"], ["expr", "expr"])
add_primitive("negative", ["expr"], ["expr"])
add_primitive("mod", ["expr"], ["int_expr", "int_expr"])
# add_primitive("arithmetic_type", ["expr"], ["arithmetic"])
add_primitive("round", ["int_expr", "expr"], ["expr"])
# base level operations
add_primitive("change_x", ["op"], ["expr"])
add_primitive("change_y", ["op"], ["expr"])
add_primitive("change_angle", ["op"], ["expr"])
add_primitive("flip_angle", ["op"], [])
add_primitive("change_speed", ["op"], ["expr"])
add_primitive("move", ["op"], [])
add_primitive("move_t", ["op"], ["expr"])
add_primitive("move_s", ["op"], ["expr"])
add_primitive("move_ts", ["op"], ["expr", "expr"])
add_primitive("move_x", ["op"], ["expr"])
add_primitive("move_y", ["op"], ["expr"])
add_primitive("move_xy", ["op"], ["expr", "expr"])
add_primitive("dot", ["op"], [])
# compositional operations
add_primitive("repeat", ["op"], ["op", "int_expr"])
add_primitive("concat", ["op"], ["op", "op"])
add_primitive("continue", ["op"], ["op"])

if USE_RECURSION
    add_primitive("var_c", ["expr"], [])
    add_primitive("subprogram", ["op"], ["op"])
end

# function definitions and applications
#add_primitive("lambda_expr", ["lambda_expr"], ["expr"]) #func which evals to expr
#add_primitive("lambda_op", ["lambda_op"], ["op"]) #func which evals to an operation.
#add_primitive("apply_expr_to_op_func", ["op"], ["op", "expr"]) #applies expr arg to op func
#add_primitive("apply_expr_to_expr_func", ["expr"], ["lambda_expr", "expr"])
#add_primitive("map_list_to_op_func", ["op"], ["op", "list"])
#add_primitive("range", ["list"], [])


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
        prim_prob = 1 / 2^(n_children_of_same_type) 
        if p in ["plus", "minus", "times", "divide", "negative", "mod"]
            prim_prob *= 1/6
        end
        if p in ["dot", "move", "move_s", "move_t", "move_x", "move_y", "move_xy", "move_ts"]
            prim_prob *= 1/8
        end
        if p in ["var_c"]
            prim_prob *= 1/20 # Penalize complex recursive concepts
        end
        if p in ["subprogram"]
            prim_prob *= 1/20 # Penalize complex recursive concepts
        end

        if "expr" in p_dict["types"]
            expr_dict[p] = prim_prob
            if "int_expr" in p_dict["types"]
                int_expr_dict[p] = prim_prob
            end
            if n_children > 0
                if p_dict["child_types"][1] == "expr"
                    expr_to_expr_c1_dict[p] = prim_prob
                end
            end
            if n_children > 1
                if p_dict["child_types"][2] == "expr"
                    expr_to_expr_c2_dict[p] = prim_prob
                end
            end
        end
        if "op" in p_dict["types"]
            op_dict[p] = prim_prob
            if n_children > 0
                if p_dict["child_types"][1] == "op"
                    op_to_op_c1_dict[p] = prim_prob
                end
            end
            if n_children > 1
                if p_dict["child_types"][2] == "op"
                    op_to_op_c2_dict[p] = prim_prob
                end
            end
        end
        if "lambda_op" in p_dict["types"]
            lambda_op_dict[p] = prim_prob
        end
        if "lambda_expr" in p_dict["types"]
            lambda_expr_dict[p] = prim_prob
        end
        if "list" in p_dict["types"]
            list_dict[p] = prim_prob
        end
        if "internal_var" in p_dict["types"]
            internal_var_dict[p] = prim_prob
        end
        if "arithmetic" in p_dict["types"]
            arithmetic_dict[p] = prim_prob
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
    if change_node.tp in ["apply_expr_to_op_func", "map_list_to_op_func"]
        return nothing
    end
    for node_tp in node_list
        if node_tp in ["apply_expr_to_op_func", "map_list_to_op_func"]
            continue
        end

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
    if length(values(prob_dict))==0
        return nothing
    else
        return dict_to_dist(prob_dict, node_list)
    end
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