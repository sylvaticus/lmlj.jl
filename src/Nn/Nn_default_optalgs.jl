
export SGD,DebugOptAlg,ADAM


# ------------------------------------------------------------------------------
# SGD
"""
  SGD(;η=t -> 1/(1+t), λ=2)

Stochastic Gradient Descent algorithm (default)

# Fields:
- `η`: Learning rate, as a function of the current epoch [def: t -> 1/(1+t)]
- `λ`: Multiplicative constant to the learning rate [def: 2]
"""
struct SGD <: OptimisationAlgorithm
    η::Function
    λ::Float64
    function SGD(;η=t -> 1/(1+t), λ=2)
        return new(η,λ)
    end
end


function singleUpdate!(θ,▽,optAlg::SGD;nEpoch,nBatch,nBatches,xbatch,ybatch)
    η    = optAlg.η(nEpoch)*optAlg.λ
    #newθ = gradSub.(θ,gradMul.(▽,η))
    θ =  θ - ▽ .* η
    #newθ = gradientDescentSingleUpdate(θ,▽,η)
    return (θ=θ,stop=false)
end

#gradientDescentSingleUpdate(θ::Number,▽::Number,η) = θ .- (η .* ▽)
#gradientDescentSingleUpdate(θ::AbstractArray,▽::AbstractArray,η) = gradientDescentSingleUpdate.(θ,▽,Ref(η))
#gradientDescentSingleUpdate(θ::Tuple,▽::Tuple,η) = gradientDescentSingleUpdate.(θ,▽,Ref(η))

#maxEpochs=1000, η=t -> 1/(1+t), λ=1, rShuffle=true, nMsgs=10, tol=0




# ------------------------------------------------------------------------------
# ADAM
#

"""
  ADAM(;η, λ, β₁, β₂, ϵ)

The [ADAM](https://arxiv.org/pdf/1412.6980.pdf) algorithm, an adaptive moment estimation optimiser.

# Fields:
- `η`:  Learning rate (stepsize, α in the paper), as a function of the current epoch [def: t -> 0.001 (i.e. fixed)]
- `λ`:  Multiplicative constant to the learning rate [def: 1]
- `β₁`: Exponential decay rate for the first moment estimate [range: ∈ [0,1], def: 0.9]
- `β₂`: Exponential decay rate for the second moment estimate [range: ∈ [0,1], def: 0.999]
- `ϵ`:  Epsilon value to avoid division by zero [def: 10^-8]
"""
mutable struct ADAM <: OptimisationAlgorithm
    η::Function
    λ::Float64
    β₁::Float64
    β₂::Float64
    ϵ::Float64
    m::Vector{Learnable}
    v::Vector{Learnable}
    function ADAM(;η=t -> 0.001, λ=1.0, β₁=0.9, β₂=0.999, ϵ=1e-8)
        return new(η,λ,β₁,β₂,ϵ,[],[])
    end
end

"""
   initOptAlg!(optAlg::ADAM;θ,batchSize,x,y,rng)

Initialize the ADAM algorithm with the parameters m and v as zeros and check parameter bounds
"""
function initOptAlg!(optAlg::ADAM;θ,batchSize,x,y,rng = Random.GLOBAL_RNG)
    optAlg.m = θ .- θ # setting to zeros
    optAlg.v = θ .- θ # setting to zeros
    if optAlg.β₁ <= 0 || optAlg.β₁ >= 1 @error "The parameter β₁ must be ∈ [0,1]" end
    if optAlg.β₂ <= 0 || optAlg.β₂ >= 1 @error "The parameter β₂ must be ∈ [0,1]" end
end

function singleUpdate!(θ,▽,optAlg::ADAM;nEpoch,nBatch,nBatches,xbatch,ybatch)
    β₁,β₂,ϵ  = optAlg.β₁, optAlg.β₂, optAlg.ϵ
    η        = optAlg.η(nEpoch)*optAlg.λ
    t        = (nEpoch-1)*nBatches+nBatch
    optAlg.m = @. β₁ * optAlg.m + (1-β₁) * ▽
    optAlg.v = @. β₂ * optAlg.v + (1-β₂) * (▽*▽)
    #optAlg.v = [β₂ .* optAlg.v.data[i] .+ (1-β₂) .* (▽.data[i] .* ▽.data[i]) for i in 1:size(optAlg.v.data)]
    m̂        = @. optAlg.m /(1-β₁^t)
    v̂        = @. optAlg.v /(1-β₂^t)
    θ        = @. θ - (η * m̂) /(sqrt(v̂)+ϵ)
    return     (θ=θ,stop=false)
end

# ------------------------------------------------------------------------------
# DebugOptAlg

struct DebugOptAlg <: OptimisationAlgorithm
    dString::String
    function DebugOptAlg(;dString="Hello World, I am a Debugging Algorithm. I done nothing to your Net.")
        return new(dString)
    end
end

function singleUpdate!(θ,▽,optAlg::DebugOptAlg;nEpoch,nBatch,batchSize,ϵ_epoch,ϵ_epoch_l)
    println(optAlg.dString)
    return (θ=θ,stop=false)
end
