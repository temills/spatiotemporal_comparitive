using Gen
import LinearAlgebra

@dist number_proposal_dist(x) = normal(x, 0.1)
@dist noise_proposal_dist(x) = exp(normal(log(x), 0.1))
@dist weights_proposal_dist(x, cov_mat) = mvnormal(x, cov_mat)

@gen function weights_proposal(trace)
    weights_x = trace[:weights_x]
    weights_y = trace[:weights_y]

    n_terms = length(weights_x)
    cov_mat = Matrix(0.05 * LinearAlgebra.I/n_terms, n_terms, n_terms)
    weights_x ~ weights_proposal_dist(weights_x, cov_mat)
    weights_y ~ weights_proposal_dist(weights_y, cov_mat)

end

@gen function noise_prog_scale_proposal(trace)
    noise_prog_scale ~ noise_proposal_dist(trace[:noise_prog_scale])
end

@gen function noise_proposals(trace)
    shape ~ noise_proposal_dist(trace[:shape])
    scale ~ noise_proposal_dist(trace[:scale])
    precision_x ~ noise_proposal_dist(trace[:precision_x])
    precision_y ~ noise_proposal_dist(trace[:precision_y])

end

@gen function weight_noise_proposals(trace)
    weight_shape ~ noise_proposal_dist(trace[:weight_shape])
    weight_scale ~ noise_proposal_dist(trace[:weight_scale])
    weight_precision ~ noise_proposal_dist(trace[:weight_precision])
end

@dist number_prior_dist() = normal(0, 3)

