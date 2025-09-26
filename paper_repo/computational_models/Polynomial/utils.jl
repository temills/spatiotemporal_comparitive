using Plots
using Gen
using Distributions
using CSV
using DataFrames

function normalize(dist)
    return dist/sum(dist)
end

function standardize(dist)
    if std(dist) > 0
        return map(k -> k - mean(dist), dist)/std(dist)
    else
        return map(k -> 0, dist)
    end
end

function round_all(xs::Vector{Float64}; n=2)
    map(x -> round(x; digits=n), xs)
end

function sample_categorical(probs::Vector{Float64})
    u = rand()
    cdf = cumsum(probs)
    for (i, c) in enumerate(cdf)
        if u < c return i end
    end
end

function dict_to_dist(dict::Dict, max_type_num::Int64)
    dist = Vector{Float64}()
    types = sort(collect(keys(dict)))
    @assert(minimum(types) > 0)
    for node_type in 1:max_type_num
        if node_type in types
            p = dict[node_type]
        else
            p = 0
        end
        append!(dist, p)
    end
    dist = normalize(dist)
    return dist
end

function printlnsep(args...; separator::String = " ")
    println([string(round(i, sigdigits=2)) * separator for i ∈ args]...)
end

function logit(p)
    log(p)-log(1-p)
end

function invlogit(a)
    1/(1+exp(-a))
end

function sigmoid(γ, x)
    γ/(1+exp(-x))
end

function generate_polynomial_terms(N, K)
    terms = Vector{Vector{Int64}}([])
    current_term = zeros(Int, K)
    
    function generate_term(index, remaining_degree)
        if index > K
            push!(terms, copy(current_term))
            return
        end
        
        for degree in 0:remaining_degree
            current_term[index] = degree
            generate_term(index + 1, remaining_degree - degree)
        end
    end
    
    generate_term(1, N)
    return terms
end

function evaluate_polynomial(variable_values, weights, polynomial_terms)
    if length(variable_values) != length(polynomial_terms[1])
        throw(ArgumentError("Variable values must match the number of terms"))
    end
    
    result = 0.0
    for i in 1:length(polynomial_terms)
        term = polynomial_terms[i]
        term_value = weights[i]
        for (v, p) in zip(variable_values, term)
            term_value *= v^p
        end
        result += term_value
    end
    
    return result
end
