"""
  Stats.jl File

Classical statistical methods implementation (Module BetaML.Stars)

`?BetaML.Stats` for documentation

- [Importable source code (most up-to-date version)](https://github.com/sylvaticus/BetaML.jl/blob/master/src/Stats.jl) - [Julia Package](https://github.com/sylvaticus/BetaML.jl)
- New to Julia? [A concise Julia tutorial](https://github.com/sylvaticus/juliatutorial) - [Julia Quick Syntax Reference book](https://julia-book.com)

"""


"""
    BetaML.Stats module

Implement classical statistical methods. EXPERIMENTAL !

The module provide the following functions. Use `?[type or function]` to access their full signature and detailed documentation:

# Hyphothesis testing

- ``: Build a single Decision Tree


Acknowlegdments: most code is based on the MITx MOOC [Fundamentals of Statistics](https://www.edx.org/course/fundamentals-of-statistics)
"""
module Stats

using LinearAlgebra, Random, Distributions

using  ForceImport
@force using ..Api
@force using ..Utils


export welchSatterthwaite, huberLoss, check, mEstimationBruteForce, findQuantile, goodnessOfFitDiscrete, ksTest, computeDensity


welchSatterthwaite(σx, σy,n,m) = Int(floor(((σx^2/n) + (σy^2/m))^2 / ( (σx^4/(n^2*(n-1)) + (σy^4/(m^2*(m-1)) ) ))))
huberLoss(x,δ=0.01) = abs(x) < δ ? x^2/2 : δ*(abs(x)-δ/2)
check(x,α) = x >=0 ? α * x : - (1- α) * x

"""
    mEstimationBruteForce(obs,candidates,lossFunction=abs)

"Solve" m-estimation in 1-D by "brute-force", i.e. by trying all the candidates provided to the function.

"""
function mEstimationBruteForce(obs,candidates,lossFunction=abs)
    score  = +Inf
    θstar = 0
    for c in candidates
      candidateScore = mean(lossFunction.(obs .- c))
      if candidateScore < score
        score = candidateScore
        θstar = c
      end
    end
    return θstar
  end



function findQuantile(obs,α;precision=0.001)
    score  = +Inf
    quantile = 0
    candidates = minimum(obs):precision:maximum(obs)
    for c in candidates
        candidateScore = mean(check.(obs .- c,α))
        if candidateScore < score
            score = candidateScore
            quantile = c
        end
    end
    return quantile
end

function goodnessOfFitDiscrete(data,p0=[1/length(data) for i in 1:length(data)];α=0.05)
    K = length(p0)
    N = sum(data)
    if length(data) != K
      @error "p0 and data must have the same number of categories!"
    end
    p̂ = data ./ N
    T = N * sum((p̂[k] - p0[k])^2/p0[k] for k in 1:K)
    χDist = Chisq(K-1)
    rejectedH₀ = T > quantile(χDist,1-α)
    p_value = 1 - cdf(χDist,T)
    return (testValue=T, threashold=quantile(χDist,1-α),rejectedH₀=rejectedH₀, p_value=p_value)
  end

function computeDensity(data,support)
    counts =  [count(i -> i==s,data) for s in support]
    if length(data) > sum(counts)
        error("There are some data not in the support !")
    end
    return counts
end

""" 
    goodnessOfFitDiscrete(data,support,f₀;compressedData=true,α=0.05,d=0)

Perform a goodness to fit chi-squared test to check for a particular MMF.

The passed distribution must support the method `pdf(dist,x)` for the provided support.
H₀ can be either the PDF with a specified set of parameters or the PDF in general. In this case the distribution object should be passed to this function with the MLE estimators that best fit the data (it is NOT done inside this function). In such case  the `d` parameter should be set to the number of estimated parameters in order to remove the `d` degree of freedom from the chi-square test.
"""
function goodnessOfFitDiscrete(data,support,f₀;compressedData=true,α=0.05,d=0)
    if !compressedData
        data   = computeDensity(data,support)
    end
    K          = length(support)
    N          = sum(data)
    p̂          = data ./ N
    df         = K - d - 1
    p0         = pdf.(f₀,support)
    T          = N * sum((p̂[k] - p0[k])^2/p0[k] for k in 1:K)
    χDist      = Chisq(df)
    rejectedH₀ = T > quantile(χDist,1-α)
    p_value    = 1 - cdf(χDist,T)
    return (testValue=T, threashold=quantile(χDist,1-α),rejectedH₀=rejectedH₀, p_value=p_value)
end

function ksTest(data,f₀;α=0.05)
    data       = sort(data)
    N          = length(data)
    cdfhat     = collect(0:N) ./ N
    maxDist    = 0.0
    for (n,x) in enumerate(data)
        dist = max(abs(cdfhat[n]-cdf(f₀,x)), abs(cdfhat[n]-cdf(f₀,x)))
        if dist > maxDist
            maxDist = dist
        end
    end
    T          = sqrt(N) * maxDist
    dist       = Kolmogorov()
    rejectedH₀ = T > quantile(dist,1-α)
    p_value    = 1 - cdf(dist,T)
    return (testValue=T, threashold=quantile(dist,1-α),rejectedH₀=rejectedH₀, p_value=p_value)
end




end # end module
