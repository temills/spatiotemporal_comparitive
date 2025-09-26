using Gen: Distribution, @dist
using Distributions

struct StudentT <: Distribution{Float64} end

const student_t = StudentT()

function Gen.random(::StudentT, μ::Real, σ::Real, ν::Real)
    tdist = TDist(ν)
    return μ + σ * rand(tdist)
end

function Gen.logpdf(::StudentT, x::Real, μ::Real, σ::Real, ν::Real)
    tdist = TDist(ν)
    scaled_x = (x - μ) / σ
    return Distributions.logpdf(tdist, scaled_x) - log(σ)
end

Gen.has_output_grad(::StudentT) = true
function Gen.logpdf_grad(::StudentT, x::Real, μ::Real, σ::Real, ν::Real)
    tdist = TDist(ν)
    scaled_x = (x - μ) / σ
    logpdf_t = Distributions.logpdf(tdist, scaled_x)
    pdf_t = exp(logpdf_t)

    deriv_x = -pdf_t * (scaled_x / σ) * ((ν + 1) / (ν + scaled_x^2))

    deriv_μ = -deriv_x
    deriv_σ = pdf_t * (scaled_x^2 / σ) * ((ν + 1) / (ν + scaled_x^2)) - (1 / σ)

    deriv_ν = 0.0

    return (deriv_x, deriv_μ, deriv_σ, deriv_ν)
end

Gen.has_argument_grads(::StudentT) = (true, true, true)

# Make the distribution callable
function (dist::StudentT)(μ::Real, σ::Real, ν::Real)
    return Gen.random(dist, μ, σ, ν)
end