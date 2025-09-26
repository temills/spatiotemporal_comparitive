""" This file contains the code for making proposals during mcmc """

####### Proposals for params ########

@gen function init_angle_proposal(trace::Trace)
    init_angle ~ normal(trace[:init_angle], 0.1)
end

@dist speed_proposal_dist(x::Float64) = exp(normal(log(x), 0.25))

@gen function init_speed_proposal(trace)
    init_speed ~ speed_proposal_dist(trace[:init_speed])
end

@gen function hyper_proposal(prev_trace, addr)
    prev_val = prev_trace[addr]
    input_left = max(0, prev_val - .1)
    input_right = min(1, prev_val + .1)
    prop_val = @trace(uniform_continuous(input_left, input_right), addr)
    return prop_val
end


@dist number_proposal_dist(x::Float64) = normal(x, 0.1)
@dist int_proposal_dist(x::Int64) = categorical(normalize(append!(fill(0.0, max(0,x-2)), [1,0,1])))
@gen function number_proposal(trace::Trace, addr_temp::Vector{Symbol}, param)
    addr = addr_temp[length(addr_temp)]
    is_int = (addr==:int_param)
    for i in length(addr_temp)-1:-1:1
        addr = addr_temp[i] => addr
    end
    if is_int
        @trace(int_proposal_dist(param), addr)
    else
        @trace(number_proposal_dist(param), addr)
    end
end

function get_param_addr_list(node::Node, addr_so_far::Vector{Symbol}, addr_list::Vector{Tuple{Vector{Symbol}, Union{Int64, Float64}}})
    if node.tp == "real"
        a = copy(addr_so_far)
        push!(addr_list, (push!(a, :param), node.params[1]))
    elseif node.tp == "int"
        a = copy(addr_so_far)
        push!(addr_list, (push!(a, :int_param), node.params[1]))
    elseif length(node.children)==1
        a = copy(addr_so_far)
        addr_list = get_param_addr_list(node.children[1], push!(a, :c1), addr_list)
    elseif length(node.children)==2
        a = copy(addr_so_far)
        b = copy(addr_so_far)
        addr_list = get_param_addr_list(node.children[1], push!(a, :c1), addr_list)
        addr_list = get_param_addr_list(node.children[2], push!(b, :c2), addr_list)
    end
    return addr_list
end


####### Proposals on tree structure ########

@gen function random_node_path(node::Node, env::Vector{String}, biased::Bool=false)
    if biased
        p_stop = (length(node.children) == 0) ? 1.0 : 0.5
    else
        p_stop = (length(node.children) == 0) ? 1.0 : 1/node.size
    end
    stop = @trace(bernoulli(p_stop), :stop)
    if stop
        return (:tree, node, env)
    else
        if length(node.children)==1
            (next_node, direction) = (node.children[1], :c1)
        elseif length(node.children)==2
            p_c1 = size(node.children[1]) / (size(node) - 1)
            (next_node, direction) = @trace(bernoulli(p_c1), :dir) ? (node.children[1], :c1) : (node.children[2], :c2)
        else
            error("Not set up for nodes with > 2 children")
        end

        if node.tp in ["apply_expr_to_op_func", "map_list_to_op_func"]
            if direction==:c1
                push!(env, "expr")
            end
        end

        # Recurse
        (rest_of_path, final_node, env) = @trace(random_node_path(next_node, env, biased), :rest_of_path)

        if isa(rest_of_path, Pair)
            return (:tree => direction => rest_of_path[2], final_node, env)
        else
            return (:tree => direction, final_node, env)
        end
    end
end

@gen function regen_random_subtree(prev_trace::Trace, propose_params::Bool)
    """
    Regenerate a random subtree
    """
    (subtree_addr, change_node, env) = @trace(random_node_path(get_retval(prev_trace), Vector{String}()), :path)
    if change_node.tp[1:2] == "bv"
        @trace(pcfg_prior("expr", change_node.parent_tp, change_node.parent_c, env), :new_subtree)
    elseif "expr" in grammar[change_node.tp]["types"]
        if grammar[change_node.parent_tp]["child_types"][change_node.parent_c] == "int_expr"
            @trace(pcfg_prior("int_expr", change_node.parent_tp, change_node.parent_c, env), :new_subtree)
        else
            @trace(pcfg_prior("expr", change_node.parent_tp, change_node.parent_c, env), :new_subtree)
        end
    else
        @assert length(grammar[change_node.tp]["types"])==1
        type_dist = grammar[change_node.tp]["types"][1]
        @trace(pcfg_prior(type_dist, change_node.parent_tp, change_node.parent_c, env), :new_subtree) 
    end

    subtree_addr_list = Vector{Symbol}()
    x = subtree_addr
    while isa(x, Pair)
        push!(subtree_addr_list, x[1])
        x = x[2]
    end
    push!(subtree_addr_list, x)
    return subtree_addr_list
end

function symb_list_to_addr(l::Vector{Symbol})
    addr = l[end]
    for i in length(l)-1:-1:1
        addr = l[i] => addr
    end
    return addr
end

function subtree_involution(trace::Trace, fwd_assmt::ChoiceMap, subtree_addr::Vector{Symbol}, proposal_args::Tuple{Bool})
    subtree_addr = symb_list_to_addr(subtree_addr)
    model_assmt = get_choices(trace)
    bwd_assmt = choicemap()
    set_submap!(bwd_assmt, :path, get_submap(fwd_assmt, :path))
    set_submap!(bwd_assmt, :new_subtree, get_submap(model_assmt, subtree_addr))
    new_trace_update = choicemap()
    set_submap!(new_trace_update, subtree_addr, get_submap(fwd_assmt, :new_subtree))

    (propose_params,) = proposal_args
    # Param proposals contingent on structure
    if propose_params
        new_trace_update = propose_params_given_structure(trace, new_trace_update)
    end

    (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), new_trace_update)
    (new_trace, bwd_assmt, weight)
end


function propose_params_given_structure(trace::Trace, new_trace_update::ChoiceMap)
    (temp_new_trace, _, _, _) = update(trace, get_args(trace), (NoChange(),), new_trace_update)
    addr_list = get_param_addr_list(temp_new_trace[:tree], [:tree], Vector{Tuple{Vector{Symbol}, Union{Int64, Float64}}}())
    for _=1:5
        temp_new_trace, = mh(temp_new_trace, init_angle_proposal, ())
        temp_new_trace, = mh(temp_new_trace, init_speed_proposal, ())
        temp_new_trace, = mh(temp_new_trace, Gen.select(:shape_x))
        temp_new_trace, = mh(temp_new_trace, Gen.select(:scale_x))
        temp_new_trace, = mh(temp_new_trace, Gen.select(:shape_y))
        temp_new_trace, = mh(temp_new_trace, Gen.select(:scale_y))
        for tup in addr_list
            temp_new_trace, = mh(temp_new_trace, number_proposal, tup)
        end
    end
    # copy into new_trace_update
    new_trace_update[:init_angle] = temp_new_trace[:init_angle]
    new_trace_update[:init_speed] = temp_new_trace[:init_angle]
    new_trace_update[:shape_x] = temp_new_trace[:shape_x]
    new_trace_update[:scale_x] = temp_new_trace[:scale_x]
    new_trace_update[:shape_y] = temp_new_trace[:shape_y]
    new_trace_update[:scale_y] = temp_new_trace[:scale_y]
    set_submap!(new_trace_update, :tree, get_submap(get_choices(temp_new_trace), :tree))
    return new_trace_update
end

@gen function swap_node(prev_trace::Trace, propose_params::Bool)
    """
    Swap a node with a new node
    """
    # Subtree address contains all random choices made in random node path unbiased
    (subtree_addr, change_node, env) = @trace(random_node_path(get_retval(prev_trace), Vector{String}(), false), :path)
    
    skip=false
    if change_node.tp[1:2]=="bv"
        skip=true
    else
        node_dist = get_node_dist_swap(change_node)
        if isnothing(node_dist)
            skip=true
        else
            @trace(categorical(node_dist), :new_node_type)
        end
    end

    subtree_addr_list = Vector{Symbol}()
    x = subtree_addr
    while isa(x, Pair)
        push!(subtree_addr_list, x[1])
        x = x[2]
    end
    push!(subtree_addr_list, x)
    return subtree_addr_list, skip
end

function swap_node_involution(trace::Trace, fwd_assmt::ChoiceMap, proposal_ret::Tuple{Vector{Symbol}, Bool}, proposal_args::Tuple{Bool})
    subtree_addr, skip = proposal_ret
    subtree_addr = symb_list_to_addr(subtree_addr)
    if skip
        (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), choicemap())
        bwd_assmt = fwd_assmt
        return (new_trace, bwd_assmt, weight)
    end
    model_assmt = get_choices(trace)
    bwd_assmt = choicemap()
    set_submap!(bwd_assmt, :path, get_submap(fwd_assmt, :path))
    bwd_assmt[:new_node_type] = model_assmt[subtree_addr=>:type]
    
    symb_list = Vector{Symbol}()
    temp_addr = subtree_addr
    while isa(temp_addr, Pair)
        push!(symb_list, temp_addr[1])
        temp_addr = temp_addr[2]
    end
    push!(symb_list, temp_addr)
    push!(symb_list, :type)
    addr = symb_list[length(symb_list)]
    for i in length(symb_list)-1:-1:1
        addr = symb_list[i] => addr
    end
    new_trace_update = choicemap()
    new_trace_update[addr] = fwd_assmt[:new_node_type]

    (propose_params,) = proposal_args
    if propose_params
        new_trace_update = propose_params_given_structure(trace, new_trace_update)
    end

    (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), new_trace_update)
    (new_trace, bwd_assmt, weight)
end



######## Add or remove a node ########
# To add:
# Randomly choose a node, and then add a new parent node above it 
# The chosen node will be its first child
# If this new parent node needs a second child, we'll generate one

# To remove:
# Randomly choose a node, then remove it and replace it with its first child
# This is only possible when the chosen node's first child is an acceptable child of its parent


@gen function get_node_no_c1(node_dist::Vector{Float64}, env::Vector{String})
    t = @trace(categorical(node_dist), :type)
    node_type = node_list[t]
    child_types = grammar[node_type]["child_types"]
    if node_type == "real"
        @trace(number_prior_dist(), :param)
    elseif node_type == "int"
        @trace(int_prior_dist(), :int_param)
    end
    if length(child_types) > 1
        @trace(pcfg_prior(child_types[2], node_type, 2, env), :c2)
    end
    return node_type
end


function get_can_remove_c1(change_node::Node)
    if length(change_node.children) == 0
        return false
    end
    if change_node.parent_tp == "root"
        return "op" in grammar[change_node.children[1].tp]["types"]
    else
        most_general_valid_type = grammar[change_node.parent_tp]["child_types"][change_node.parent_c]
        #if the child can be classified as this type, we can replace the node with its child
        return most_general_valid_type in get_node_types(change_node.children[1].tp)
    end
end

@gen function random_node_path_for_remove_c1(node::Node, env::Vector{String})
    if length(node.children)==0
        p_stop = 1
    elseif get_can_remove_c1(node)
        p_stop = 0.5
    else
        p_stop = 0
    end
    if @trace(bernoulli(p_stop), :stop)
        return (:tree, node, env)
    else
        if length(node.children)==1
            (next_node, direction) = (node.children[1], :c1)
        elseif length(node.children)==2
            p_c1 = size(node.children[1]) / (size(node) - 1)
            (next_node, direction) = @trace(bernoulli(p_c1), :dir) ? (node.children[1], :c1) : (node.children[2], :c2)
        end

        # Add any new bvs to env?
        if node.tp in ["apply_expr_to_op_func", "map_list_to_op_func"]#["lambda_op", "lambda_expr"]
            if direction==:c1
                push!(env, "expr")
            end
        end

        (rest_of_path, final_node) = @trace(random_node_path_for_remove_c1(next_node, env), :rest_of_path)

        if isa(rest_of_path, Pair)
            return (:tree => direction => rest_of_path[2], final_node, env)
        else
            return (:tree => direction, final_node, env)
        end
    end
end

@gen function get_new_exprs(node::Node, env, n::Int)
    exprs = []
    for i=1:n
        expr = @trace(pcfg_prior("expr", node.parent_tp, node.parent_c, env), (i, :expr))
        push!(exprs, expr)
    end
    return exprs
end

function get_bv_addr_list(node::Node, bv_str::String, addr_so_far::Vector{Symbol}=Vector{Symbol}(), addr_list::Vector{Vector{Symbol}}=Vector{Vector{Symbol}}())
    if node.tp == bv_str
        a = copy(addr_so_far)
        push!(addr_list, a)
    elseif length(node.children)==1
        a = copy(addr_so_far)
        addr_list = get_bv_addr_list(node.children[1], bv_str, push!(a, :c1), addr_list)
    elseif length(node.children)==2
        a = copy(addr_so_far)
        b = copy(addr_so_far)
        addr_list = get_bv_addr_list(node.children[1], bv_str, push!(a, :c1), addr_list)
        addr_list = get_bv_addr_list(node.children[2], bv_str, push!(b, :c2), addr_list)
    end
    return addr_list
end

function get_bv_to_expr_addrs(node::Node, bv_str::String)
    temp_addrs = get_bv_addr_list(node, bv_str)
    addrs = []
    for temp_addr in temp_addrs
        addr = temp_addr[length(temp_addr)]
        for i in length(temp_addr)-1:-1:1
            addr = temp_addr[i] => addr
        end
        push!(addrs, addr)
    end
    return addrs
end


@gen function choose_paths_to_bvs(node::Node)
    # Stack for iterative traversal
    stack = [(node, 1, Vector{Symbol}())]  # (current node, current index, address so far)
    addr_list = Vector{Vector{Symbol}}()
    while !isempty(stack)
        # Pop a node from the stack
        current_node, curr_idx, addr_so_far = pop!(stack)
        change = false
        # If it's an expression node, decide whether to change
        if "expr" in get_node_types(current_node.tp)
            change = @trace(bernoulli(0.2), (curr_idx, :change))
        end
        if change
            # Record the address
            push!(addr_list, copy(addr_so_far))
        else
            # Continue traversing
            if length(current_node.children) == 1
                # Add the single child to the stack
                push!(stack, (current_node.children[1], curr_idx * 2, push!(copy(addr_so_far), :c1)))
            elseif length(current_node.children) == 2
                # Add both children to the stack
                push!(stack, (current_node.children[2], curr_idx * 2 + 1, push!(copy(addr_so_far), :c2)))
                push!(stack, (current_node.children[1], curr_idx * 2, push!(copy(addr_so_far), :c1)))
            end
        end
    end

    return addr_list
end

# When we remove a node, we need to figure out the reverse choices
# Basically, traverse the tree and at each bv idx store change as true 
# and at each expr idx that is not a bv, we store change as false
function get_bv_to_expr_change_tups(node::Node, bv_str::String, curr_idx=1, tup_list::Vector{Tuple{Int,Bool}}=Vector{Tuple{Int,Bool}}())
    #from this we want the list of (idx, :change) vals
    change = false
    if ("expr" in get_node_types(node.tp))
        change = (node.tp == bv_str)
        push!(tup_list, (curr_idx, change))
    end
    if !change #continue traversing if we didn't change it
        if length(node.children)==1
            tup_list = get_bv_to_expr_change_tups(node.children[1], bv_str, curr_idx*2, tup_list)
        elseif length(node.children)==2
            tup_list = get_bv_to_expr_change_tups(node.children[1], bv_str, curr_idx*2, tup_list)
            #if we're on the first node, we actually don't care about its second child
            #if curr_idx>1
            tup_list = get_bv_to_expr_change_tups(node.children[2], bv_str, (curr_idx*2)+1, tup_list)
            #end
        end
    end
    return tup_list
end

@gen function add_or_remove_c1(prev_trace::Trace, propose_params::Bool)
    (subtree_addr, change_node, env) = @trace(random_node_path_for_remove_c1(get_retval(prev_trace), Vector{String}()), :path)
    if get_can_remove_c1(change_node)
        add_prob = 0.3 
    else
        add_prob = 1
    end
    add ~ bernoulli(add_prob)
    skip = false
    expr_to_bv_addrs = []
    bv_to_expr_addrs = []
    bv_to_expr_change_tups = []
    new_expr_subtrees = []
    update_bvs = false
    bv_idx = length(env)+1
    if add
        node_dist = get_node_dist_add_c1(change_node)
        if isnothing(node_dist)
            skip = true
        else
            new_parent_type = @trace(get_node_no_c1(node_dist, env), :new_subtree)
            # If the node we want to add as a parent is map or app,
            # then we also need to allow creation of bvs
            if new_parent_type in ["apply_expr_to_op_func", "map_list_to_op_func"]
                update_bvs = true
                temp_addrs = @trace(choose_paths_to_bvs(change_node), :expr_to_bv_paths)
                expr_to_bv_addrs = []
                for temp_addr in temp_addrs
                    addr = temp_addr[length(temp_addr)]
                    for i in length(temp_addr)-1:-1:1
                        addr = temp_addr[i] => addr
                    end
                    push!(expr_to_bv_addrs, addr)
                end
            end
        end
    else
        if change_node.tp in ["apply_expr_to_op_func", "map_list_to_op_func"]
            # If we remove a map or app, we need to remove its bvs
            update_bvs = true
            bv_str = "bv_" * string(bv_idx)
            bv_to_expr_addrs = get_bv_to_expr_addrs(change_node.children[1], bv_str)
            bv_to_expr_change_tups = get_bv_to_expr_change_tups(change_node.children[1], bv_str)
            new_expr_subtrees = @trace(get_new_exprs(change_node, env, length(bv_to_expr_addrs)), :new_expr_subtrees)
        end
    end
    subtree_addr_list = Vector{Symbol}()
    x = subtree_addr
    while isa(x, Pair)
        push!(subtree_addr_list, x[1])
        x = x[2]
    end
    push!(subtree_addr_list, x)
    return subtree_addr_list, skip, update_bvs, expr_to_bv_addrs, bv_to_expr_addrs, bv_to_expr_change_tups, bv_idx
end

function copy_choicemap(old_map)
    new_map = choicemap()
    for (addr, val) in get_values_shallow(old_map)
        new_map[addr] = old_map[addr]
    end
    for (addr, submap) in get_submaps_shallow(old_map)
        set_submap!(new_map, addr, copy_choicemap(submap))
    end
    return new_map
end

function inc_bv_idxs(map, min_tp)
    for (addr, val) in get_values_shallow(map)
        if (addr==:type) & (val >= min_tp)
            map[addr] = val+1
        end
    end
    for (addr, submap) in get_submaps_shallow(map)
        set_submap!(map, addr, inc_bv_idxs(submap, min_tp))
    end
    return map
end

function dec_bv_idxs(map, min_tp)
    for (addr, val) in get_values_shallow(map)
        if (addr==:type) & ((val >= min_tp))
            map[addr] = val-1
        end
    end
    for (addr, submap) in get_submaps_shallow(map)
        set_submap!(map, addr, dec_bv_idxs(submap, min_tp))
    end
    return map
end

function add_or_remove_involution_c1(trace::Trace, fwd_assmt::ChoiceMap, proposal_ret, proposal_args::Tuple{Bool})
    """
    Add a parent node, or remove the given node and replace w child
    """
    subtree_addr, skip, update_bvs, expr_to_bv_addrs, bv_to_expr_addrs, bv_to_expr_change_tups, bv_idx = proposal_ret
    subtree_addr = symb_list_to_addr(subtree_addr)
    if skip
        (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), choicemap())
        bwd_assmt = fwd_assmt
        return (new_trace, bwd_assmt, weight)
    end
    model_assmt = get_choices(trace)
    bwd_assmt = choicemap()
    set_submap!(bwd_assmt, :path, get_submap(fwd_assmt, :path))
    bwd_assmt[:add] = ~(fwd_assmt[:add])

    # Add node
    if fwd_assmt[:add]
        my_map = choicemap()
        my_map[:type] = get_value(get_submap(fwd_assmt, :new_subtree), :type)
        c2_map = get_submap(fwd_assmt, :new_subtree => :c2)
        if ~isempty(c2_map)
            set_submap!(my_map, :c2, c2_map)
        end
        c1_choices_temp = get_submap(model_assmt, subtree_addr)
        c1_choices = copy_choicemap(c1_choices_temp)

        # Add bvs to c1_choices
        if update_bvs
            c1_choices = inc_bv_idxs(c1_choices, length(node_list)+bv_idx)
            # For each identified address, change expr to bv in c1
            n_changes = length(expr_to_bv_addrs)
            for i=1:n_changes
                bv_addr = expr_to_bv_addrs[i]
                # Store the old expr currently at this addr
                prev_expr = get_submap(c1_choices, bv_addr)
                set_submap!(bwd_assmt, :new_expr_subtrees=>(i,:expr), prev_expr)
                # Replace it with the next bv
                bv_map = choicemap((:type, length(node_list)+bv_idx))
                set_submap!(c1_choices, bv_addr, bv_map) 
            end
            # Set c1 to changenode
            set_submap!(my_map, :c1, c1_choices)
            new_trace_update = choicemap()
            # Insert at subtree addr in new_trace_update
            set_submap!(new_trace_update, subtree_addr, my_map)        
            (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), new_trace_update)
        else
            # Set c1 to the changenode
            set_submap!(my_map, :c1, c1_choices)
            new_trace_update = choicemap()
            # Insert at subtree addr in new_trace_update
            set_submap!(new_trace_update, subtree_addr, my_map)
            (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), new_trace_update)
        end
    else
        c1_map = copy_choicemap(get_submap(model_assmt, subtree_addr=>:c1))
        # Replace bvs with exprs
        if update_bvs
            # Removing a node, so later bv idxs decrease by one
            c1_map = dec_bv_idxs(c1_map, length(node_list)+bv_idx)
            n = length(bv_to_expr_addrs)
            # Replace bvs with sampled exprs
            for i=1:n
                bv_addr = bv_to_expr_addrs[i]
                new_expr_subtree = get_submap(fwd_assmt, :new_expr_subtrees=>(i,:expr))
                set_submap!(c1_map, bv_addr, new_expr_subtree)
            end
            tmp = choicemap()
            for (idx, change) in bv_to_expr_change_tups
                tmp[(idx, :change)] = (change==1)
            end
            set_submap!(bwd_assmt, :expr_to_bv_paths, tmp)
        end
        new_trace_update = choicemap()
        set_submap!(new_trace_update, subtree_addr, c1_map)
        
        my_map = choicemap()
        my_map[:type] = get_value(model_assmt, subtree_addr => :type)
        c2_map = get_submap(model_assmt, subtree_addr => :c2)
        if ~isempty(c2_map)
            set_submap!(my_map, :c2, c2_map)
        end
        set_submap!(bwd_assmt, :new_subtree, my_map)
        (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), new_trace_update)
    end

    (new_trace, bwd_assmt, weight)
end


######## add or remove a node, c2 (analogous to c1) ########
# for add:
# so, randomly choose a node, and then add a new parent node above it 
# the chosen node will be its SECOND child
# generate a first child for the parent node

# for remove:
# randomly choose a node, then remove it and replace it with its SECOND child
# this is only possible when the chosen node's second child is an acceptable child of its parent

@gen function get_node_no_c2(node_dist::Vector{Float64}, env::Vector{String})
    t = @trace(categorical(node_dist), :type)
    node_type = node_list[t]
    child_types = grammar[node_type]["child_types"]
    if node_type == "real"
        @trace(number_prior_dist(), :param)
    elseif node_type == "int"
        @trace(int_prior_dist(), :int_param)
    end
    if length(child_types) > 0
        @trace(pcfg_prior(child_types[1], node_type, 1, env), :c1)
    end
end

function get_can_remove_c2(change_node::Node)
    if length(change_node.children) < 2
        return false
    end
    if change_node.parent_tp == "root"
        return "op" in grammar[change_node.children[2].tp]["types"]
    else
        most_general_valid_type = grammar[change_node.parent_tp]["child_types"][change_node.parent_c]
        # if the child is of this type, we can replace the node with its child
        return most_general_valid_type in get_node_types(change_node.children[2].tp)
    end
end

@gen function random_node_path_for_remove_c2(node::Node, env::Vector{String})
    if length(node.children)==0
        p_stop = 1
    elseif get_can_remove_c2(node)
        p_stop = 0.5
    else
        p_stop = 0
    end

    if @trace(bernoulli(p_stop), :stop)
        return (:tree, node, env)
    else
        if length(node.children)==1
            (next_node, direction) = (node.children[1], :c1)
        elseif length(node.children)==2
            p_c1 = size(node.children[1]) / (size(node) - 1)
            (next_node, direction) = @trace(bernoulli(p_c1), :dir) ? (node.children[1], :c1) : (node.children[2], :c2)
        else
            error("Not set up for nodes with > 2 children")
        end

        # Add any new bvs to env
        if node.tp in ["apply_expr_to_op_func", "map_list_to_op_func"]
            if direction==:c1
                push!(env, "expr")
            end
        end

        (rest_of_path, final_node) = {:rest_of_path} ~ random_node_path_for_remove_c2(next_node, env)

        if isa(rest_of_path, Pair)
            return (:tree => direction => rest_of_path[2], final_node, env)
        else
            return (:tree => direction, final_node, env)
        end
    end
end


@gen function add_or_remove_c2(prev_trace::Trace, propose_params::Bool)
    (subtree_addr, change_node, env) = @trace(random_node_path_for_remove_c2(get_retval(prev_trace), Vector{String}()), :path)
    if get_can_remove_c2(change_node)
        add_prob = 0.3
    else
        add_prob = 1
    end
    add ~ bernoulli(add_prob)
    
    skip=false
    if add
        node_dist = get_node_dist_add_c2(change_node)
        if isnothing(node_dist)
            skip = true
        else
            @trace(get_node_no_c2(node_dist, env), :new_subtree)
        end
    end

    subtree_addr_list = Vector{Symbol}()
    x = subtree_addr
    while isa(x, Pair)
        push!(subtree_addr_list, x[1])
        x = x[2]
    end
    push!(subtree_addr_list, x)
    return subtree_addr_list, skip
end


function add_or_remove_involution_c2(trace::Trace, fwd_assmt::ChoiceMap, proposal_ret::Tuple{Vector{Symbol}, Bool}, proposal_args::Tuple{Bool})
    subtree_addr, skip = proposal_ret
    subtree_addr = symb_list_to_addr(subtree_addr)
    if skip
        (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), choicemap())
        bwd_assmt = fwd_assmt
        return (new_trace, bwd_assmt, weight)
    end
    model_assmt = get_choices(trace)
    bwd_assmt = choicemap()
    set_submap!(bwd_assmt, :path, get_submap(fwd_assmt, :path))
    bwd_assmt[:add] = ~(fwd_assmt[:add])

    # Add node
    if fwd_assmt[:add]
        my_map = choicemap()
        my_map[:type] = get_value(get_submap(fwd_assmt, :new_subtree), :type)
        set_submap!(my_map, :c2, get_submap(model_assmt, subtree_addr))
        set_submap!(my_map, :c1, get_submap(fwd_assmt, :new_subtree => :c1))
        new_trace_update = choicemap()
        set_submap!(new_trace_update, subtree_addr, my_map)
    # Remove node
    else
        c2_map = get_submap(model_assmt, subtree_addr=>:c2)
        new_trace_update = choicemap()
        set_submap!(new_trace_update, subtree_addr, c2_map)
        my_map = choicemap()
        my_map[:type] = get_value(model_assmt, subtree_addr => :type)
        set_submap!(my_map, :c1, get_submap(model_assmt, subtree_addr => :c1))
        set_submap!(bwd_assmt, :new_subtree, my_map)
    end

    (propose_params,) = proposal_args
    if propose_params
        new_trace_update = propose_params_given_structure(trace, new_trace_update)
    end

    (new_trace, weight, _, _) = update(trace, get_args(trace), (NoChange(),), new_trace_update)

    (new_trace, bwd_assmt, weight)
end