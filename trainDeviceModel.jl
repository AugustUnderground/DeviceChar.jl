#####################
## Dependencies
#####################

using Dates
using Random
using Statistics
using Plots
using StatsBase
using Distributions
using DataFrames
using JLD2
using BSON
using CUDA
using MLDataUtils
using Zygote
using Flux
using Flux: @epochs
using Logging
using Printf: @printf
using NumericIO
using Chain
#using Lazy
#using OhMyREPL

######################
## Setup
######################

# File System
timeStamp = string(Dates.now());
dataDir = "../data/";
deviceType = :p;
deviceName = "ptmp45"; # "ptmn90";
modelDir = "./model/" * deviceName * "-" * timeStamp * "/";
mosFile = dataDir * deviceName * ".jld";
modelFile = modelDir * deviceName * ".bson";
Base.Filesystem.mkdir(modelDir);

# Don't allow scalar operations on GPU
CUDA.allowscalar(false);

# Set Plot Backend
#unicodeplots();
inspectdr();

# RNGesus Seed
rngSeed = 666;

######################
## Data
######################

# Handle JLD2 dataframe
dataFrame = jldopen(mosFile, "r") do file
    file["database"];
end;

# Processing, Fitlering, Sampling and Shuffling
dataFrame.QVgs = dataFrame.Vgs.^2.0;
dataFrame.EVds = ℯ.^(dataFrame.Vds);
dataFrame.RVbs = abs.(dataFrame.Vbs).^0.5;

# Define Features and Outputs
paramsX = ["W", "L", "Vgs", "QVgs", "Vds", "EVds", "Vbs", "RVbs"];
paramsY = ["vth", "vdsat", "id", "gm", "gmb", "gds", "fug"];
paramsZ = ["cgd", "cgb", "cgs", "cds", "csb", "cdb"];

#paramsY = ["vth", "vdsat", "id", "gm", "gmb", "gds", "fug"
#          , "cgd", "cgb", "cgs", "cds", "csb", "cdb" ];

#paramsXY = names(dataFrame);
#paramsX = filter((p) -> isuppercase(first(p)), paramsXY);
#paramsY = filter((p) -> !in(p, paramsX), paramsXY);

# Number of In- and Outputs, for respective NN Layers
numX = length(paramsX);
numY = length(paramsY);
numZ = length(paramsZ);
numYZ = numY + numZ;

## Sample Data for appropriate distribution

# Single weighted Sample
#idxSamples = StatsBase.sample( MersenneTwister(rngSeed)
#                             , 1:size(dataFrame, 1)
#                             , StatsBase.pweights(dataFrame.id)
#                             , 666666
#                             ; replace = false 
#                             , ordered = false );
#df = dataFrame[idxSamples, : ];

# Sample half of Data in Saturation Region with probability weighted id
satN = dataFrame.Vds .>= (dataFrame.Vgs .- dataFrame.vth);
satP = dataFrame.Vds .<= (dataFrame.Vgs .+ dataFrame.vth);
sdf = dataFrame[(deviceType == :n ? satN : satP) , :];
sSamp = sdf[ StatsBase.sample( MersenneTwister(rngSeed)
                             , 1:size(sdf, 1)
                             , pweights(sdf.id)
                             , 3000000
                             ; replace = false
                             , ordered = false )
           , : ];

# Sample half of Data in Triode Region without weights
triN = dataFrame.Vds .<= (dataFrame.Vgs .- dataFrame.vth);
triP = dataFrame.Vds .>= (dataFrame.Vgs .+ dataFrame.vth);
tdf = dataFrame[(deviceType == :n ? triN : triP) , :];
tSamp = tdf[ StatsBase.sample( MersenneTwister(rngSeed)
                             , 1:size(tdf, 1)
                             #, pweights(tdf.id)
                             , 1000000
                             ; replace = false
                             , ordered = false )
           , : ];

# Join samples and shuffle all observations
df = shuffleobs(vcat(tSamp, sSamp));

# Box-Cox-Transformation Functions
boxCox(yᵢ; λ = 0.2) = λ != 0 ? (((yᵢ.^λ) .- 1) ./ λ) : log.(yᵢ);
coxBox(y′; λ = 0.2) = λ != 0 ? exp.(log.((λ .* y′) .+ 1) / λ) : exp.(y′);

# Split into Features and Outputs
rawX = Matrix(df[:, paramsX ])';
rawY = Matrix(df[:, paramsY ])';
rawZ = Matrix(df[:, paramsZ ])';

# Apply Box Cox transformation to outputs (negative C's don't make sense)
λ = 0.2;
coxY = boxCox.(rawY; λ = λ);
coxZ = boxCox.(abs.(rawZ); λ = λ);

# Scale all observations to unit range
utX = StatsBase.fit(UnitRangeTransform, rawX; dims = 2, unit = true); 
utY = StatsBase.fit(UnitRangeTransform, coxY; dims = 2, unit = true); 
utZ = StatsBase.fit(UnitRangeTransform, coxZ; dims = 2, unit = true); 
#utY = StatsBase.fit(UnitRangeTransform, rawY; dims = 2, unit = true); 

# Transform all data to be ∈  [0;1]
dataX = StatsBase.transform(utX, rawX);
dataY = [ StatsBase.transform(utY, coxY)
        ; StatsBase.transform(utZ, coxZ) ];
#dataY = StatsBase.transform(utY, rawY);

# Split data in training and validation set
splitRatio = 0.8;
trainX,validX = splitobs(dataX, splitRatio);
trainY,validY = splitobs(dataY, splitRatio);

# Create training and validation Batches
batchSize = 2000;
trainSet = Flux.Data.DataLoader( (trainX, trainY)
                               , batchsize = batchSize
                               , shuffle = true );
validSet = Flux.Data.DataLoader( (validX, validY)
                               , batchsize = batchSize
                               , shuffle = true );

######################
## Model
######################

# Neural Network
φ = Flux.Chain( Flux.Dense(numX   , 128   , Flux.relu)
              , Flux.Dense(128    , 256   , Flux.relu) 
              , Flux.Dense(256    , 512   , Flux.relu) 
              , Flux.Dense(512    , 1024  , Flux.relu) 
              , Flux.Dense(1024   , 512   , Flux.relu) 
              , Flux.Dense(512    , 256   , Flux.relu) 
              , Flux.Dense(256    , 128   , Flux.relu) 
              , Flux.Dense(128    , numYZ , Flux.relu) 
              ) |> gpu;

# Optimizer Parameters
η   = 0.001;
β₁  = 0.9;
β₂  = 0.999;

# ADAM Optimizer
optim = Flux.Optimise.ADAM(η, (β₁, β₂)) |> gpu;

######################
## Training
######################

# Loss/Objective/Cost function for Training and Validation
mse(x, y) = Flux.Losses.mse(φ(x), y, agg = mean);
mae(x, y) = Flux.Losses.mae(φ(x), y, agg = mean);

# Model Parameters (Weights)
θ = Flux.params(φ) |> gpu;

# Training Loop
function trainModel()
    trainMSE = map(trainSet) do batch               # iterate over batches in train set
        gpuBatch = batch |> gpu;                    # make sure batch is on GPU
        error,back = Flux.Zygote.pullback(() -> mse(gpuBatch...), θ);
        ∇ = back(one(error |> cpu)) |> gpu;         # gradient based on error
        Flux.update!(optim, θ, ∇);                  # update weights
        return error;                               # return MSE
    end;
    validMAE = map(validSet) do batch               # no gradients required
        gpuBatch = batch |> gpu;
        error,back = Flux.Zygote.pullback(() -> mae(gpuBatch...), θ);
        return error;                               # iterate over validation data set
    end;
    meanMSE = mean(trainMSE);                       # get mean training error over epoch
    meanMAE = mean(validMAE);                       # get mean validation error over epoch
    @printf( "[%s] MSE = %s and MAE = %s\n"
           , Dates.format(now(), "HH:MM:SS")
           , formatted(meanMSE, :ENG, ndigits = 4) 
           , formatted(meanMAE, :ENG, ndigits = 4) )
    if meanMAE < lowestMAE                          # if model has improved
        bson( modelFile                             # save the current model (cpu)
            , name = deviceName
            , type = deviceType
            , model = (φ |> cpu) 
            , paramsX = paramsX
            , paramsY = paramsY
            , paramsZ = paramsZ
            , utX = utX
            , utY = utY 
            , utZ = utZ 
            , lambda = λ );
        global lowestMAE = meanMAE;                 # update previous lowest MAE
        @printf( "\tNew Model Saved with MAE: %s\n" 
               , formatted(meanMAE, :ENG, ndigits = 4) )
    end
    return [meanMSE meanMAE];                       # mean of error for all batches
end;

### Run Training
numEpochs = 100;                                    # total number of epochs
lowestMAE = Inf;                                    # initialize MAE with ∞
errs = [];                                          # Array of training and validation losses

@epochs numEpochs push!(errs, trainModel())         # Run Training Loop for #epochs

# Reshape errors for a plotting
losses = @chain errs begin
             vcat(_...)
             Float64.()
         end;

# Plot Training Process
plot( 1:numEpochs, losses
    ; lab = ["MSE" "MAE"]
    , title = "$(deviceName) Training"
    , xaxis = "# Epoch", yaxis = "Error"
    , w = 2 )

######################
## Evaluation
######################

## Use current model ###
φ = φ |> cpu;
######################

## Load specific model ##
#modelFile = "./model/ptmp90-2021-02-12T08:49:20.636/ptmp90.bson"
model   = BSON.load(modelFile);
φ       = model[:model];
paramsX = model[:paramsX];
paramsY = model[:paramsY];
paramsZ = model[:paramsZ];
numX    = length(paramsX);
numY    = length(paramsY);
numZ    = length(paramsZ);
utX     = model[:utX];
utY     = model[:utY];
utZ     = model[:utZ];
λ       = model[:lambda];
######################

## Load DB in case ##
if !@isdefined(dataFrame)
    deviceName = model[:name];
    dataFrame = jldopen( f -> f["database"]
                       , "../data/" * deviceName * ".jld"
                       , "r" );
end
######################

# Round DB for better Plotting
dataFrame.Vgs = round.(dataFrame.Vgs, digits = 2);
dataFrame.Vds = round.(dataFrame.Vds, digits = 2);
dataFrame.Vbs = round.(dataFrame.Vbs, digits = 2);

boxCox(yᵢ; λ = 0.2) = λ != 0 ? (((yᵢ.^λ) .- 1) ./ λ) : log.(yᵢ);
coxBox(y′; λ = 0.2) = λ != 0 ? exp.(log.((λ .* y′) .+ 1) / λ) : exp.(y′);

function predict(X)
    X′ = StatsBase.transform(utX, X)
    YZ′ = φ(X′)
    Y′ = YZ′[1:numY, :];
    Z′ = YZ′[(numY+1):end, :];
    Y = coxBox.(StatsBase.reconstruct(utY, Y′); λ = λ );
    Z = coxBox.(StatsBase.reconstruct(utZ, Z′); λ = λ );
    return DataFrame(Float64.(hcat(Y',Z')), String.([paramsY ; paramsZ]))
end;

# Arbitrary Operating Point and sizing
vgs = 0.0:0.01:1.2;
qvgs = vgs.^2.0;
vds = 0.0:0.01:1.2;
evds = exp.(vds);
len = length(vgs);
W = rand(filter(w -> w > 2.0e-6, unique(dataFrame.W)));
L = rand(filter(l -> l < 1.0e-6, unique(dataFrame.L)));
VG = 0.6;
VD = 0.6;
VB = 0.0;
vbc = zeros(len);
w = fill(W, len);
l = fill(L, len);
vgc = fill(VG, len);
qvgc = vgc.^2.0;
vdc = fill(VD, len);
evdc = exp.(vdc);
rvbc = sqrt.(abs.(vbc));

## Transfer Characterisitc

# Input matrix for φ according to paramsX
xt = [ w l vgs qvgs vdc evdc vbc rvbc ]';

# Ground Truth from original Database
idtTrue = @chain dataFrame begin
            _[ ( (_.W .== W)
              .& (_.L .== L)
              .& (_.Vbs .== VB)
              .& (_.Vds .== VD))
             , ["id" , "Vgs"] ]
            sort(:Vgs)
            _[:id]
          end;

# Prediction from φ
yt = predict(xt);
idtPred = yt.id;

## Output Characterisitc

# Input matrix for φ according to paramsX
xo = [ w l vgc qvgc vds evds vbc rvbc ]';

# Ground Truth from original Database
idoTrue = @chain dataFrame begin
            _[ ( (_.W .== W)
              .& (_.L .== L)
              .& (_.Vbs .== VB)
              .& (_.Vgs .== VG))
             , ["id" , "Vds"] ]
            sort(:Vds)
            _[:id]
          end;

# Prediction from φ 
yo = predict(xo);
idoPred = yo.id;

## Plot Results
inspectdr();

Wf = formatted(W, :ENG, ndigits = 2);
Lf = formatted(L, :ENG, ndigits = 2);
plot( plot( collect(vgs), [idtTrue idtPred]
          ; title = "TFC @ Vds = $(VD) W = $(Wf), L = $(Lf)" 
          , xaxis = "Vgs [V]", yaxis = "Id [A]" )
    , plot( collect(vds), [ idoTrue idoPred ]
          ; title = "OPC @ Vgs = $(VG) W = $(Wf), L = $(Lf)" 
          , xaxis = "Vds [V]", yaxis = "Id [A]" )
    , layout = (2,1), w = 2 )
