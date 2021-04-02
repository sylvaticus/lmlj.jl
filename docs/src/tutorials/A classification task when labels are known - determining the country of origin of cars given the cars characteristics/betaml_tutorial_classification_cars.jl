# # [A classification task when labels are known - determining the country of origin of cars given the cars characteristics](@id classification_tutorial)

# In this exercise we have some car technical characteristics (mpg, horsepower,weight, model year...) and the country of origin and we want to create a model such that the country of origin can be accurately predicted given the technical characteristics.

#
# Data origin:
# - dataset description: [https://archive.ics.uci.edu/ml/datasets/auto+mpg](https://archive.ics.uci.edu/ml/datasets/auto+mpg)
#src Also useful: https://www.rpubs.com/dksmith01/cars
# - data source we use here: [https://archive.ics.uci.edu/ml/machine-learning-databases/auto-mpg/auto-mpg.data](https://archive.ics.uci.edu/ml/machine-learning-databases/auto-mpg/auto-mpg.data)

# field description

# 1. mpg:           continuous
# 2. cylinders:     multi-valued discrete
# 3. displacement:  continuous
# 4. horsepower:    continuous
# 5. weight:        continuous
# 6. acceleration:  continuous
# 7. model year:    multi-valued discrete
# 8. origin:        multi-valued discrete
# 9. car name:      string (unique for each instance) - not used here



# ## Library and data loading

# We load a buch of packages that we'll use during this tutorial..
using Random, HTTP, CSV, DataFrames, BenchmarkTools, BetaML
import DecisionTree, Flux
import Pipe: @pipe
using  Test     #src

# To load the data from the internet our workflow is
# (1) Retrieve the data -> (2) Clean it -> (3) Load it -> (4) Output it as a DataFrame

# For step 1 we use HTTP.get(), for step (2) we use `replace!`, for steps (3) and (4) we uses the CSV package, and we use the "pip" `|>` operator to chain these operations:

urlDataOriginal = "https://archive.ics.uci.edu/ml/machine-learning-databases/auto-mpg/auto-mpg.data-original"
data = @pipe HTTP.get(urlDataOriginal).body                                                |>
             replace!(_, UInt8('\t') => UInt8(' '))                                        |>
             CSV.File(_, delim=' ', missingstring="NA", ignorerepeated=true, header=false) |>
             DataFrame;

# This results in a table where the rows are the observations (the various cars) and the column the fields. All BetaML models expect this layout.
# As the dataset is ordered, we randomly shuffle the data. Note that we pass to shuffle `copy(FIXEDRNG)` as the random nuber generator in order to obtain reproducible output.
data[shuffle(copy(FIXEDRNG),axes(data, 1)), :]
describe(data)

# Columns 1 to 7 contain  characteristics of the car, while column 8 encodes the country or origin ("1" -> US, "2" -> EU, "3" -> Japan) that we want to be able to predict.
# Columns 9 contains the car name, but we are not going to use this information in this tutorial.
# Note also that some fields have missing data.
# Our first step is hence to divide the dataset in features (the x) and the labels (the y) we want to predict. The `x` is then a Julia standard `Matrix` of 406 rows by 7 columns and the `y` is a vector of the 406 observations:
x     = Matrix{Union{Missing,Float64}}(data[:,1:7]);
y     = Vector{Int64}(data[:,8]);

# Some algorithms that we will use today don't like missing data, so we need to _impute_ them. Foir this we are using the [`predictMissing`](@ref) function provided by the [`Clustering`](@ref) sub-module. Internally it uses a Gaussian Mixture Model to assign to the missing walue of a given record an average of the values of the non-missing records weighted for how much close they are to our specific record.
xFull = predictMissing(x,3,rng=copy(FIXEDRNG)).X̂;
# Further, some models don't work with categorical data as such, so we need to represent our y as a matrix with a separate column for each possible value (the so called "one-hot" representation). To encode as one-hot we use the function [`oneHotEncoder`](@ref) in submodule [`BetaML.Utils`](@ref)
y_oh  = oneHotEncoder(y); ## Convert to One-hot representation (e.g. 2 => [0 1 0], 3 => [0 0 1])

# In supervised machine learning it is good practice to partition the available data in a _training_, _validation_, and _test_ subsets, where the first one is used to train the ML algorithm, the second one to train any eventual "hyperparameters" of the algorithm and the _test_ subset is finally used to evaluate the quality of the algorithm.
# Here, for brevity, we use only the _train_ and the _test_ subsets, implicitly assuming we already know the best hyperparameters. Please refer to the [regression tutorial](@ref regression_tutorial) for examples of how to use the validation subset to train the hyperparameters.
# We use then the [`partition`](@ref) function, where we can specify the different data to partition (that must have the same number of observations) and the shares of observation that we want in each subset.
((xtrain,xtest),(xtrainFull,xtestFull),(ytrain,ytest),(ytrain_oh,ytest_oh)) = partition([x,xFull,y,y_oh],[0.8,1-0.8],rng=copy(FIXEDRNG));

# ## Random Forests

# We are now ready to use our first model, the Random Forests (in the [`BetaML.Trees`](@ref) sub_module) [Random Forests](@ref BetaML.Trees). Random Forests build a "forest" of decision trees models and then use their averaged predictions to make a overall prediction out of a feature matrix.
# To "build" the forest model (i.e. to "train" it) we need to give the model the training feature matrix and the associated "true" training labels, and we need to specify the number of trees to use (this is an example of hyperparameters). Here we use 30 individual decision trees.
# As the labels are encoded using integers,  we need also to use the parameter `forceClassification=true` otherwide the model would undergo a _regression_ job.
myForest       = buildForest(xtrain,ytrain,30, rng=copy(FIXEDRNG),forceClassification=true);
# To obtain the predicted values, we can simply use the function [`BetaML.Trees.predict`](@ref)
#src [`predict`](@ref BetaML.Trees.predict)  [`predict`](@ref forest_prediction)
# with our `myForest` model and either the training or testing data.
ŷtrain,ŷtest   = predict.(Ref(myForest), [xtrain,xtest],rng=copy(FIXEDRNG));
# Finally we can measure the _accuracy_ of our predictions with the [`accuracy`](@ref) function:
trainAccuracy,testAccuracy  = accuracy.([parse.(Int64,mode(ŷtrain)),parse.(Int64,mode(ŷtest))],[ytrain,ytest])
#src (0.9969230769230769,0.8024691358024691)
# The predictions are quite good, for the training set the algoritm predicted almost all cars' origins correctly, while for the testing set (i.e. those records that has **not** been used to train the algorithm), the correct prediction level is still quite high, at 80%
# When we benchmark the resourse used (time and memory) we find that Random Forests remain pretty fast, expecially when we compare them with neural networks (see later)
@btime buildForest(xtrain,ytrain,30, rng=copy(FIXEDRNG),forceClassification=true);
#src   128.335 ms (781027 allocations: 196.30 MiB)



# ### Comparision with DecisionTree.jl

# DecisionTrees.jl random forests are similar in usage: we first "build" (train) the forest and we then make predictions out of the trained model.
# The main difference is that the model requires data with nonmissing values, so we are going to use the `xtrainFull` and `xtestFull` feature labels we created earlier:
## We train the model...
model = DecisionTree.build_forest(ytrain, xtrainFull,-1,30,rng=123)
## ..and we generate predictions and measure their error
(ŷtrain,ŷtest) = DecisionTree.apply_forest.([model],[xtrainFull,xtestFull]);
(trainAccuracy,testAccuracy) = accuracy.([ŷtrain,ŷtest],[ytrain,ytest])
#src (0.9969230769230769, 0.7530864197530864)
# While the accuracy on the training set is exactly the same as for `BetaML` random forets, `DecisionTree.jl` random forests are slighly less accurate in the testing sample.
# Where however `DecisionTrees.jl` excell is in the efficiency: they are extremelly fast and memory parse, even if here to this benchmark we should add the resources need to impute the missing values. Also, one of the reasons DecisionTrees are such efficient is that internally they sort the data to avoid repeated comparision, but in this way they work only with features that are sortable, while BetaML random forests accept virtually any kind of input without the need of adapt it.
@btime  DecisionTree.build_forest(ytrain, xtrainFull,-1,30,rng=123);
#src 1.451 ms (10875 allocations: 1.52 MiB)



# ### Neural network

# Neural networks (NN) can be very powerfull, but have two "inconvenients" compared with random forests: First, are a bit "picky". We need to do a bit of work to provide data in specific format. Note that this is _not_ feature engineering. One of the advantages on neural network is that for the most this is not needed for neural networks. However we still need to "clean" the data. One issue is that NN don't like missing data. So we need to provide them with the feature matrix "clean" of missing data. Secondly, they work only with numerical data. So we need to use the one-hot encoding we saw earlier.
#Further, they work best if the features are scaled such that each feature has mean zero and standard deviation 1. We can achieve it with the function [`scale`](@ref) or, as in this case, [`getScaleFactors`](@ref).
xScaleFactors   = getScaleFactors(xtrainFull)
D               = size(xtrainFull,2)
classes         = unique(y)
nCl             = length(classes)

# The second "inconvenient" of NN i that, while not requiring feature engineering, they stil lneed a bit of practice on the way to build the network. It's not as simple as `train(model,x,y)`. We need here to specify how we want our layers, _chain_ the layers together and then decide a _loss_ overall function. Only when we done these steps, we have the model ready for training.
# Here we define 3 [`DenseLayer`](@ref) zwhere, for each of them, we specify the number of neurons in input (the first layer being equal to the dimensions of the data), the output layer (for a classification task, the last layer output size beying equal to the number of classes) and an _activation function for each layer (default the `identity` function).
ls   = 80
l1   = DenseLayer(D,ls,f=relu,rng=copy(FIXEDRNG)) ## Activation function is ReLU
l2   = DenseLayer(ls,ls,f=relu,rng=copy(FIXEDRNG))
l3   = DenseLayer(ls,nCl,f=relu,rng=copy(FIXEDRNG))
# For a classification the last layer is a [`VectorFunctionLayer`](@ref) that has no learnable parameters but whose activation function is applied to the ensemble of the neurons, rather than individually on each neuron. In particular, for classification we pass the [`BetaML.Utils.softmax`](@ref) function whose output has the same size as the input (and the number of classes to predict), but we can use the `VectorFunctionLayer` with any function, including the [`pool1d`](@ref) function to create a "pooling" layer (using maximum, mean or whatever other subfunction we pass to `pool1d`)
l4   = VectorFunctionLayer(nCl,f=softmax) ## Add a (parameterless) layer whose activation function (softMax in this case) is defined to all its nodes at once
# Finally we _chain_ the layers and assign a loss function
mynn = buildNetwork([l1,l2,l3],squaredCost,name="Multinomial logistic regression Model Cars") ## Build the NN and use the squared cost (aka MSE) as error function (crossEntropy could also be used)

# Now we can train our network using the function [`train!`](@ref). It has many options, have a look at the documentation for all the possible arguments.
# Note that we trained the network based on the scaled feature matrix
res = train!(mynn,scale(xtrainFull,xScaleFactors),ytrain_oh,epochs=300,batchSize=16,rng=copy(FIXEDRNG)) ## Use optAlg=SGD() to use Stochastic Gradient Descent instead

# Once trained, we can predict the label. As the trained was based on the scaled feature matrix, so must be for the predictions
(ŷtrain,ŷtest)  = predict.(Ref(mynn),[scale(xtrainFull,xScaleFactors),scale(xtestFull,xScaleFactors)])
(trainAccuracy,testAccuracy) = accuracy.([ŷtrain,ŷtest],[ytrain,ytest])
#src (0.9753846153846154,0.8765432098765432)

# With neural networks the tesst accuracy improves of 7 percentual points.
# However this come with a large computational cost, at the training takes now several seconds:
@btime train!(mynn,scale(xtrainFull),ytrain_oh,epochs=300,batchSize=8,rng=copy(FIXEDRNG),verbosity=NONE);
#src 11.147 s (18322340 allocations: 21.72 GiB)


# ### Comparisons with Flux

# In Flux the input bust be in the form (fields, observations), so we transpose our original matrices
xtrainT, ytrain_ohT = transpose.([scale(xtrainFull,xScaleFactors), ytrain_oh])
xtestT, ytest_ohT = transpose.([scale(xtestFull,xScaleFactors), ytest_oh])


# We define the Flux neural network model in a similar way than BetaML and load it with data, we train it, predict and measure the accuracies on the training and the test sets:

#src function poolForFlux(x,wsize=5)
#src     hcat([pool1d(x[:,i],wsize;f=maximum) for i in 1:size(x,2)]...)
#src end
Random.seed!(123)

l1         = Flux.Dense(D,ls,Flux.relu)
l2         = Flux.Dense(ls,ls,Flux.relu)
l3         = Flux.Dense(ls,nCl,Flux.relu)
Flux_nn    = Flux.Chain(l1,l2,l3)
loss(x, y) = Flux.logitcrossentropy(Flux_nn(x), y)
ps         = Flux.params(Flux_nn)
nndata     = Flux.Data.DataLoader((xtrainT, ytrain_ohT), batchsize=16,shuffle=true)
begin for i in 1:300  Flux.train!(loss, ps, nndata, Flux.ADAM()) end end
ŷtrain     = Flux.onecold(Flux_nn(xtrainT),1:3)
ŷtest      = Flux.onecold(Flux_nn(xtestT),1:3)
(trainAccuracy,testAccuracy) = accuracy.([ŷtrain,ŷtest],[ytrain,ytest])
# While the train accuracy is the same as in BetaML, the test accuracy is somehow lower

# However the time is again lower than BetaML, even if here for "just" a factor 2
@btime begin for i in 1:300 Flux.train!(loss, ps, nndata, Flux.ADAM()) end end;
#src 5.385 s (3623163 allocations: 1.55 GiB)


# ## Summary

# This is the summary of the results we had trying to predict the country of origin of the cars, based on their technical characteristics:

# | Model                | Train acc     | Test Acc |  Training time (ms) | Training mem (MB) |
# |:-------------------- |:-------------:| --------:| ------------------- | ----------------- |
# | RF                   | 0.9969        | 0.8025   | 133                 | 196               |
# | RF (DecisionTree.jl) | 0.9969        | 0.7531   | 1.4                 | 1.5               |
# | NN                   | 0.9754        | 0.8765   | 10684               | 22241             |
# | NN (Flux.jl)         | 0.9692        | 0.7284   | 9164                | 1577              |

# We find a similar situation as in the bike's demand [regression tutorial](@ref): neural networks can be more precise than random forests models, but are more computationally expensive (and tricky to set up). When we compare BetaML with the algorithm-specific leading packages, we found similar results in terms of accuracy, but often the leading packages are better optimised and run more efficiently (but sometimes at the cost of being less verstatile).
