"""
  Trees.jl File

Decision Trees implementation (Module BetaML.Trees)

`?BetaML.Trees` for documentation

- [Importable source code (most up-to-date version)](https://github.com/sylvaticus/BetaML.jl/blob/master/src/Trees.jl) - [Julia Package](https://github.com/sylvaticus/BetaML.jl)
- New to Julia? [A concise Julia tutorial](https://github.com/sylvaticus/juliatutorial) - [Julia Quick Syntax Reference book](https://julia-book.com)

"""


"""
    BetaML.Trees module

Implement the functionality required to build a Decision Tree or a whole Random Forest, predict data and assess its performances.

Both Decision Trees and Random Forests can be used for regression or classification problems, based on the type of the labels (numerical or not). You can override the automatic selection with the parameter `forceClassification=true`, typically if your labels are integer representing some categories rather than numbers.

Missing data on features are supported.

Based originally on the [Josh Gordon's code](https://www.youtube.com/watch?v=LDRbO9a6XPU)

The module provide the following functions. Use `?[type or function]` to access their full signature and detailed documentation:

# Model definition and training:

- `buildTree`: Build a single Decision Tree
- `buildForest`: Build a "forest" of Decision Trees


# Model predictions and assessment:

- `predict`: Return the prediction given the feature matrix
- `Utils.accuracy(tree or forest)`: Categorical output accuracy
- `Utils.mearRelError(tree or forest,p)`: L-p norm based error

Features are expected to be in the standard format (nRecords × nDimensions matrices) and the labels (either categorical or numerical) as a nRecords column vector.
"""
module Trees

using LinearAlgebra, Random, Statistics, Reexport
@reexport using ..Utils

export buildTree, buildForest, predict, print
import Base.print

"""
   Question

A question used to partition a dataset.

This struct just records a 'column number' and a 'column value' (e.g., Green).
"""
mutable struct Question
    column
    value
end

function print(question::Question)
    condition = "=="
    if isa(question.value, Number)
        condition = ">="
    end
    print("Is col $(question.column) $condition $(question.value) ?")
end

"""
   Leaf(y,depth)

A tree's leaf (terminal) node.

# Constructor's arguments:
- `y`: The labels assorciated to each record (either numerical or categorical)
- `depth`: The nodes's depth in the tree

# Struct members:
- `rawPredictions`: Either the label's count or the numerical labels of the members of the node
- `predictions`: Either the relative label's count (i.e. a PMF) or the mean
- `depth`: The nodes's depth in the tree
"""
mutable struct Leaf
    rawPredictions
    predictions
    depth
    function Leaf(y,depth)
        if eltype(y) <: Number
            rawPredictions = y
            predictions     = mean(rawPredictions)
        else
            rawPredictions = classCounts(y)
            total = sum(values(rawPredictions))
            predictions = Dict{eltype(y),Float64}()
            [predictions[k] = rawPredictions[k] / total for k in keys(rawPredictions)]
        end
        return new(rawPredictions,predictions,depth)
    end
end

"""


A Decision Node asks a question.

This holds a reference to the question, and to the two child nodes.
"""


"""
   DecisionNode(question,trueBranch,falseBranch, depth)

A tree's non-terminal node.

# Constructor's arguments and struct members:
- `question`: The question asked in this node
- `trueBranch`: A reference to the "true" branch of the trees
- `falseBranch`: A reference to the "false" branch of the trees
- `depth`: The nodes's depth in the tree
"""
mutable struct DecisionNode
    question
    trueBranch
    falseBranch
    depth
    function DecisionNode(question,trueBranch,falseBranch, depth)
        return new(question,trueBranch,falseBranch, depth)
    end
end


"""

   match(question, x)

Return a dicotomic answer of a question when applied to a given feature record.

It compares the feature value in the given record to the value stored in the
question.
Numerical features are compared in terms of disequality (">="), while categorical features are compared in terms of equality ("==").
"""
function match(question, x)
    val = x[question.column]
    if isa(val, Number) # or isa(val, AbstractFloat) to consider "numeric" only floats
        return val >= question.value
    else
        return val == question.value
    end
end

"""
   partition(question,x)

Dicotomically partitions a dataset `x` given a question.

For each row in the dataset, check if it matches the question. If so, add it to 'true rows', otherwise, add it to 'false rows'.
Rows with missing values on the question column are assigned randomply proportionally to the assignment of the non-missing rows.
"""
function partition(question::Question,x)
    N = size(x,1)
    trueIdx = fill(false,N); falseIdx = fill(false,N); missingIdx = fill(false,N)
    for (rIdx,row) in enumerate(eachrow(x))
        #println(row)
        if(ismissing(row[question.column]))
            missingIdx[rIdx] = true
        elseif match(question,row)
            trueIdx[rIdx] = true
        else
            falseIdx[rIdx] = true
        end
    end
    # Assigning missing rows randomly proportionally to non-missing rows
    p = sum(trueIdx)/(sum(trueIdx)+sum(falseIdx))
    r = rand(N)
    for rIdx in 1:N
        if missingIdx[rIdx]
            if r[rIdx] <= p
                trueIdx[rIdx] = true
            else
                falseIdx[rIdx] = true
            end
        end
    end
    return trueIdx, falseIdx
end



"""

   infoGain(left, right, parentUncertainty; splittingCriterion)

Compute the information gain of a specific partition.

Compare the "information gain" my measuring the difference betwwen the "impurity" of the labels of the parent node with those of the two child nodes, weighted by the respective number of items.

# Parameters:
- `leftY`:  Child #1 labels
- `rightY`: Child #2 labels
- `parentUncertainty`: "Impurity" of the labels of the parent node
- `splittingCriterion`: Metrics to adopt to determine the "impurity" (see below)

Three "impurity" metrics are supported:
- `gini` (categorical)
- `entropy` (categorical)
- `variance` (numerical)

"""
function infoGain(leftY, rightY, parentUncertainty; splittingCriterion)
    p = size(leftY,1) / (size(leftY,1) + size(rightY,1))
    popvar(x) = var(x,corrected=false)
    critFunction = giniImpurity
    if splittingCriterion == "gini"
        critFunction = giniImpurity
    elseif splittingCriterion == "entropy"
        critFunction = entropy
    elseif splittingCriterion == "variance"
        critFunction = popvar
    else
        @error "Splitting criterion not supported"
    end
    return parentUncertainty - p * critFunction(leftY) - (1 - p) * critFunction(rightY)
end

"""
   findBestSplit(x,y;maxFeatures,splittingCriterion)

Find the best possible split of the database.

Find the best question to ask by iterating over every feature / value and calculating the information gain.

# Parameters:
- `x`: The feature dataset
- `y`: The labels dataset
- `maxFeatures`: Maximum number of (random) features to look up for the "best split"
- `splittingCriterion`: The metric to define the "impurity" of the labels

"""
function findBestSplit(x,y;maxFeatures,splittingCriterion)
    bestGain           = 0  # keep track of the best information gain
    bestQuestion       = nothing  # keep train of the feature / value that produced it
    if splittingCriterion == "gini"
        currentUncertainty = giniImpurity(y)
    elseif splittingCriterion == "entropy"
        currentUncertainty = entropy(y)
    elseif splittingCriterion == "variance"
        currentUncertainty = var(y,corrected=false)
    else
        @error "Splitting criterion not defined"
    end
    D  = size(x,2)  # number of columns (the last column is the label)

    for d in shuffle(1:D)[1:maxFeatures]      # for each feature (we consider only maxFeatures features randomly)
        values = Set(skipmissing(x[:,d]))  # unique values in the column
        for val in values  # for each value
            question = Question(d, val)
            # try splitting the dataset
            #println(question)
            trueIdx, falseIdx = partition(question,x)
            # Skip this split if it doesn't divide the
            # dataset.
            if sum(trueIdx) == 0 || sum(falseIdx) == 0
                continue
            end
            # Calculate the information gain from this split
            gain = infoGain(y[trueIdx], y[falseIdx], currentUncertainty, splittingCriterion=splittingCriterion)
            # You actually can use '>' instead of '>=' here
            # but I wanted the tree to look a certain way for our
            # toy dataset.
            if gain >= bestGain
                bestGain, bestQuestion = gain, question
            end
        end
    end
    return bestGain, bestQuestion
end


"""

   buildTree(x, y, depth; maxDepth, minGain, minRecords, maxFeatures, splittingCriterion, forceClassification)

Builds (define and train) a Decision Tree.

Given a dataset of features `x` and the corresponding dataset of labels `y`, recursivelly build a decision tree by finding at each node the best question to split the data untill either all the dataset is separated or a terminal condition is reached.
The given tree is then returned.

# Parameters:
- `x`: The dataset's features (N × D)
- `y`: The dataset's labels (N × 1)
- `depth`: The current tree's depth. Used when calling the function recursively [def: `1`]
- `maxDepth`: The maximum depth the tree is allowed to reach. When this is reached the node is forced to become a leaf [def: `N`, i.e. no limits]
- `minGain`: The minimum information gain to allow for a node's partition [def: `0`]
- `minRecords`:  The minimum number of records a node must holds to consider for a partition of it [def: `2`]
- `maxFeatures`: The maximum number of (random) features to consider at each partitioning [def: `D`, i.e. look at all features]
- `splittingCriterion`: Either `gini`, `entropy` or `variance` (see [`infoGain`](@ref) ) [def: `gini` for categorical labels (classification task) and `variance` for numerical labels(regression task)]
- `forceClassification`: Weather to force a classification task even if the labels are numerical (typically when labels are integers encoding some feature rather than representing a real cardinal measure) [def: `false`]

# Notes:

Missing data (in the feature dataset) are supported.
"""
function buildTree(x, y, depth=1; maxDepth = size(x,1), minGain=0.0, minRecords=2, maxFeatures=size(x,2), splittingCriterion = eltype(y) <: Number ? "variance" : "gini", forceClassification=false)

    # Force what would be a regression task into a classification task
    if forceClassification && eltype(y) <: Number
        y = string.(y)
    end

    # Check if this branch has still the minimum number of records required and we are reached the maxDepth allowed. In case, declare it a leaf
    if size(x,1) <= minRecords || depth >= maxDepth return Leaf(y, depth) end

    # Try partitioing the dataset on each of the unique attribute,
    # calculate the information gain,
    # and return the question that produces the highest gain.
    gain, question = findBestSplit(x,y;maxFeatures=maxFeatures,splittingCriterion=splittingCriterion)

    # Base case: no further info gain
    # Since we can ask no further questions,
    # we'll return a leaf.
    if gain <= minGain  return Leaf(y, depth)  end

    # If we reach here, we have found a useful feature / value
    # to partition on.
    trueIdx, falseIdx = partition(question,x)

    # Recursively build the true branch.
    trueBranch = buildTree(x[trueIdx,:], y[trueIdx], depth+1, maxDepth=maxDepth, minGain=minGain, minRecords=minRecords, maxFeatures=maxFeatures, splittingCriterion=splittingCriterion, forceClassification=forceClassification)

    # Recursively build the false branch.
    falseBranch = buildTree(x[falseIdx,:], y[falseIdx], depth+1, maxDepth=maxDepth, minGain=minGain, minRecords=minRecords, maxFeatures=maxFeatures, splittingCriterion=splittingCriterion, forceClassification=forceClassification)

    # Return a Question node.
    # This records the best feature / value to ask at this point,
    # as well as the branches to follow
    # dependingo on the answer.
    return DecisionNode(question, trueBranch, falseBranch, depth)
end


"""
  print(node)

Print a Decision Tree (textual)

"""
function print(node::Union{Leaf,DecisionNode}, rootDepth="")

    depth     = node.depth
    fullDepth = rootDepth*string(depth)*"."
    spacing   = ""
    if depth  == 1
        println("*** Printing Decision Tree: ***")
    else
        spacing = join(["\t" for i in 1:depth],"")
    end

    # Base case: we've reached a leaf
    if typeof(node) == Leaf
        println("  $(node.predictions)")
        return
    end

    # Print the question at this node
    print("\n$spacing$fullDepth ")
    print(node.question)
    print("\n")

    # Call this function recursively on the true branch
    print(spacing * "--> True :")
    print(node.trueBranch, fullDepth)

    # Call this function recursively on the false branch
    print(spacing * "--> False:")
    print(node.falseBranch, fullDepth)
end


"""
predictSingle(tree,x)

Predict the label of a single feature record. See [`predict`](@ref).

"""
function predictSingle(node::Union{DecisionNode,Leaf}, x)
    # Base case: we've reached a leaf
    if typeof(node) == Leaf
        return node.predictions
    end
    # Decide whether to follow the true-branch or the false-branch.
    # Compare the feature / value stored in the node,
    # to the example we're considering.
    if match(node.question,x)
        return predictSingle(node.trueBranch,x)
    else
        return predictSingle(node.falseBranch,x)
    end
end

"""
   predict(tree,x)

Predict the labels of a feature dataset.

For each record of the dataset, recursivelly traverse the tree to find the prediction most opportune for the given record.
If the labels the tree has been trained with are numeric, the prediction is also numeric.
If the labels were categorical, the prediction is a dictionary with the probabilities of each item.

In the first case (numerical predictions) use `meanRelError(ŷ,y)` to assess the mean relative error, in the second case you can use `accuracy(ŷ,y)`.
"""
function predict(tree::Union{DecisionNode, Leaf}, x)
    predictions = predictSingle.(Ref(tree),eachrow(x))
    return predictions
end

"""
   buildForest(x, y, nTrees; maxDepth, minGain, minRecords, maxFeatures, splittingCriterion, forceClassification)

Builds (define and train) a "forest of Decision Trees.

See [`buildForest`](@ref). The parameters are exactly the same except here we have `nTrees` to define the number of trees in the forest [def: `30`] and the `maxFeatures` default to `√D` instead of `D`.

Each individual decision tree is built using bootstrap over the data, i.e. "sampling N records with replacement" (hence, some records appear multiple times and some records do not appear in the specific tree training). The `maxFeature` to square of the features inject further variability and reduce the correlation between the forest trees.

The predictions of the "forest" are then the aggregated predictions of the individual trees (from which the name "bagging": **b**oostrap **agg**regat**ing**).
"""

function buildForest(x, y, nTrees=30; maxDepth = size(x,1), minGain=0.0, minRecords=2, maxFeatures=Int(round(sqrt(size(x,2)))), splittingCriterion = eltype(y) <: Number ? "variance" : "gini", forceClassification=false)
    forest = Union{DecisionNode,Leaf}[]
    (N,D) = size(x)
    for i in 1:nTrees
        toSample = rand(1:N,N)
        boostedx = x[toSample,:]
        boostedy = y[toSample]
        tree = buildTree(boostedx, boostedy; maxDepth = maxDepth, minGain=minGain, minRecords=minRecords, maxFeatures=maxFeatures, splittingCriterion = splittingCriterion, forceClassification=forceClassification)
        push!(forest,tree)
    end
    return forest
end

"""
predictSingle(forest,x)

Predict the label of a single feature record. See [`predict`](@ref).

"""
function predictSingle(forest::Array{Union{DecisionNode,Leaf},1}, x)
    predictions  = predictSingle.(forest,Ref(x))
    if eltype(predictions) <: AbstractDict   # categorical
        return meanDicts(predictions)
    else
        return mean(predictions)
    end
end

"""
   predict(forest,x)

Predict the labels of a feature dataset.

For each record of the dataset and each tree of the "forest", recursivelly traverse the tree to find the prediction most opportune for the given record.
If the labels the tree has been trained with are numeric, the prediction is also numeric (the mean of the different trees predictions, in turn the mean of the labels of the training records ended in that leaf node).
If the labels were categorical, the prediction is a dictionary with the probabilities of each item (again the probabilities of the different trees are averaged to compose the forest predictions).

In the first case (numerical predictions) use `meanRelError(ŷ,y)` to assess the mean relative error, in the second case you can use `accuracy(ŷ,y)`.

"""
function predict(forest::Array{Union{DecisionNode,Leaf},1}, x)
    predictions = predictSingle.(Ref(forest),eachrow(x))
    return predictions
end


end