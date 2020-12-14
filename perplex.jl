### A Pluto.jl notebook ###
# v0.12.17

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ bf21b8ec-357f-11eb-023f-6b64f6e0da73
using DataFrames, StatsBase, JLD2, Plots, PlutoUI, DataInterpolations, Flux, Zygote, CUDA, BSON, PyCall, ScikitLearn, NNlib

# ╔═╡ 5b9d18dc-3e19-11eb-03e9-9f231903bd84
begin
	Core.eval(Main, :(using PyCall))
	Core.eval(Main, :(using Zygote))
	Core.eval(Main, :(using CUDA))
	Core.eval(Main, :(using NNlib))
	Core.eval(Main, :(using Flux))
end

# ╔═╡ 9f08514e-357f-11eb-2d48-a5d0177bcc4f
#begin
#	import DarkMode
#	config = Dict( "tabSize" => 4
#				 , "keyMap" => "vim" );
#	DarkMode.enable( theme = "ayu-mirage"
#				   , cm_config = config	)
#end

# ╔═╡ 5d549288-3a0c-11eb-0ac3-595f54266cb3
#DarkMode.themes

# ╔═╡ 472a5f78-3a1c-11eb-31da-9fe4b67106e4
md"""
## gm / id (Data Base)
"""

# ╔═╡ d091d5e2-357f-11eb-385b-252f9ee49070
simData = jldopen("../data/ptmn90.jld") do file
	file["database"];
end;

# ╔═╡ ed7ac13e-357f-11eb-170b-31a27207af5f
simData.Vgs = round.(simData.Vgs, digits = 2);

# ╔═╡ a002f77c-3580-11eb-0ad8-e946d85c84c7
begin
	slVds = @bind vds Slider( 0.01 : 0.01 : 1.20
							, default = 0.6, show_value = true );
	slW = @bind w Slider( 1.0e-6 : 2.5e-7 : 5.0e-6
						, default = 1.0e-6, show_value = true );
	slL = @bind l Slider( 3.0e-7 : 1.0e-7 : 1.5e-6
						, default = 3.0e-7, show_value = true );
	
	md"""
	vds = $(slVds)
	
	W = $(slW)
	
	L = $(slL)
	"""
end

# ╔═╡ 092d49d4-3584-11eb-226b-bde1f2e49a22
begin
	dd = simData[ ( (simData.Vds .== vds)
			 	 .& (simData.W .== w) )
				, ["W", "L", "gm", "gds", "id", "vdsat", "fug"] ];
	dd.idw = dd.id ./ dd.W;
	dd.gmid = dd.gm ./ dd.id;
	dd.a0 = dd.gm ./ dd.gds;
end;

# ╔═╡ 24a21870-360b-11eb-1269-db94fecdb0a6
begin
	idwgmid = plot();
	for len in 1.5e-7 : 1.0e-7 : 1.5e-6
		idwgmid = plot!( dd[dd.L .== len, "gmid"]
			 	   	   , dd[dd.L .== len, "idw"]
			 	   	   , yscale = :log10
				   	   , lab = "L = " *string(len)
				       , legend = false
			 	       , yaxis = "id/W", xaxis = "gm/id" );
	end;
	idwgmid
end;

# ╔═╡ c6232b50-360b-11eb-18a2-39bdc25fb03b
begin
	idwvdsat = plot();
	for len in 1.5e-7 : 1.0e-7 : 1.5e-6
		idwvdsat = plot!( dd[dd.L .== len, "vdsat"]
			 	       	, dd[dd.L .== len, "idw"]
			 	   		, yscale = :log10
				   		, lab = "L = " *string(len)
				   		, legend = false
			 	   		, yaxis = "id/W", xaxis = "vdsat" );
	end;
	idwvdsat
end;

# ╔═╡ cff6fad6-360b-11eb-3e9b-a7cf6a270f8f
begin
	a0gmid = plot();
	for len in 1.5e-7 : 1.0e-7 : 1.5e-6
		a0gmid = plot!( dd[dd.L .== len, "gmid"]
			 	   	  , dd[dd.L .== len, "a0"]
			 	      , yscale = :log10
				      , lab = "L = " *string(len)
				      , legend = false
			 	      , yaxis = "A0", xaxis = "gm/id" );
	end;
	a0gmid
end;

# ╔═╡ d1b49f7e-360b-11eb-2b4d-b5a6ab46505e
begin
	a0vdsat = plot();
	for len in 1.5e-7 : 1.0e-7 : 1.5e-6
		a0vdsat = plot!( dd[dd.L .== len, "vdsat"]
			 	   	   , dd[dd.L .== len, "a0"]
			 	   	   , yscale = :log10
				   	   , lab = "L = " *string(len)
				   	   , legend = false
			 	   	   , yaxis = "A0", xaxis = "vdsat" );
	end;
	a0vdsat
end;

# ╔═╡ d34046d6-360b-11eb-31cd-6378f8c1729c
begin
	ftgmid = plot();
	for len in 1.5e-7 : 1.0e-7 : 1.5e-6
		ftgmid = plot!( dd[dd.L .== len, "gmid"]
			 	   	  , dd[dd.L .== len, "fug"]
			 	   	  , yscale = :log10
				   	  , lab = "L = " *string(len)
				   	  , legend = false
			 	   	  , yaxis = "fug", xaxis = "gmid" );
	end;
	ftgmid
end;

# ╔═╡ d46c5e3c-360b-11eb-3ab7-9dc5eeb107d6
begin
	ftvdsat = plot();
	for len in 1.5e-7 : 1.0e-7 : 1.5e-6
		ftvdsat = plot!( dd[dd.L .== len, "vdsat"]
			 	   	   , dd[dd.L .== len, "fug"]
			 	   	   , yscale = :log10
				   	   , lab = "L = " *string(len)
				   	   , legend = false
			 	   	   , yaxis = "fug", xaxis = "vdsat" );
	end;
	ftvdsat
end;

# ╔═╡ 293aad98-3587-11eb-0f56-1d8144ad7e84
plot(idwgmid, idwvdsat, a0gmid, a0vdsat, ftgmid, ftvdsat, layout = (3,2))

# ╔═╡ 0282c34c-3580-11eb-28c5-e5badd2c345f
df = simData[ ( (simData.Vds .== vds)
			 .& (simData.L .== l)
			 .& (simData.W .== w) )
			, ["W", "L", "gm", "gds", "id", "vdsat"] ];

# ╔═╡ 6b97b4f0-3580-11eb-28e5-b356737b0905
begin
	df.idw = df.id ./ df.W;
	df.gmid = df.gm ./ df.id;
	df.a0 = df.gm ./ df.gds;
end;

# ╔═╡ 3cf1f458-3a1c-11eb-2d51-a70a21c10295
md"""
## gm / id (Neural Network)
"""

# ╔═╡ 49e8abac-3e18-11eb-28ca-f9af0718950d
begin
	modelFile = "./model/dev-2020-12-14T14:11:03.212/ptmn90.bson";
	model = BSON.load(modelFile);
	φ = model[:model];
	θ = model[:weights];
	trafoX = model[:inputTrafo];
	trafoY = model[:outputTrafo];
end;

# ╔═╡ 219e21a4-3e1d-11eb-2a02-fd152e843650
function predict(X)
 	rY = ((length(size(X)) < 2) ? [X'] : X') |>
         trafoX.transform |> 
         adjoint |> gpu |> φ |> cpu |> adjoint |>
         trafoY.inverse_transform |> 
         adjoint
  	return Float64.(rY)
end

# ╔═╡ f2dc08a6-3a1e-11eb-08b3-81a2ce43c86a
begin
	scVds = @bind cvds Slider( 0.01 : 0.01 : 1.20
							, default = 0.6, show_value = true );
	scVgs = @bind cvgs Slider( 0.01 : 0.01 : 1.20
							, default = 0.6, show_value = true );
	scW = @bind cw Slider( 7.5e-7 : 1.0e-7 : 5.0e-6
						, default = 5.0e-7, show_value = true );
	scL = @bind cl Slider( 1.5e-7 : 1.0e-7 : 1.5e-6
						, default = 1.5e-7, show_value = true );
	
	md"""
	vds = $(scVds)
	
	W = $(scW)
	
	L = $(scL)
	"""
end

# ╔═╡ 99fb92e4-3e1d-11eb-3120-7b09e7d9a257
begin
	paramsXY = names(simData);
	paramsX = filter((p) -> isuppercase(first(p)), paramsXY);
	paramsY = filter((p) -> !in(p, paramsX), paramsXY);
end;

# ╔═╡ 5d9312be-3e1d-11eb-184e-6fc51d067282
# Arbitrary Operating Point and sizing
vg = 0.0:0.01:1.2;

# ╔═╡ c6073d4a-3e1d-11eb-3262-df23bbe50cea
vd = 0.0:0.01:1.2;

# ╔═╡ c60af316-3e1d-11eb-238c-d5ef097d9875
# Input matrix for φ according to paramsX
xt = [ collect(vg)'
     ; repeat([cvds], 121)'
     ; zeros(1, 121)
     ; repeat([cw], 121)'
     ; repeat([cl], 121)' ];

# ╔═╡ af61e62c-3e24-11eb-38ec-57b4fc56b734


# ╔═╡ 8357b576-3e23-11eb-2198-b70b086ce536
xt |> trafoX.transform

# ╔═╡ c6168438-3e1d-11eb-293e-f7115be86ef0
# Prediction from φ
#idtPred  = predict(xt)[first(indexin(["id"], paramsY)),:];

# ╔═╡ c6173aca-3e1d-11eb-38d8-db7ac755d1e5
# Input matrix for φ according to paramsX
xo = [ repeat([cvgs], 121)'
     ; collect(vd)'
     ; zeros(1, 121)
     ; repeat([cw], 121)'
     ; repeat([cl], 121)' ];

# ╔═╡ c62ad834-3e1d-11eb-02ca-537556743757
# Prediction from φ 
#idoPred = predict(xo)[first(indexin(["id"], paramsY)),:];

# ╔═╡ c62c56fa-3e1d-11eb-2312-8d30f6aab8c8
## Plot Results

# Plot Transfer Characterisitc
#plot( vgs, [ idtTrue idtPred ]
#    , xaxis=("V_gs", (0.0, 1.2))
#    , yaxis=("I_d", (0.0, ceil( max(idtTrue...)
#                              , digits = 4 )))
#    , label=["tru" "prd"] )

# ╔═╡ c64c98d4-3e1d-11eb-2e66-13d6365eaff7
# Plot Transfer Characterisitc
#plot( vds, [ idoTrue idoPred ]
#    , xaxis=("V_ds", (0.0, 1.2))
#    , yaxis=("I_d", (0.0, ceil( max(idoTrue...)
#                              , digits = 4 )))
#    , label=["tru" "prd"])

# ╔═╡ Cell order:
# ╠═9f08514e-357f-11eb-2d48-a5d0177bcc4f
# ╠═5d549288-3a0c-11eb-0ac3-595f54266cb3
# ╠═472a5f78-3a1c-11eb-31da-9fe4b67106e4
# ╠═bf21b8ec-357f-11eb-023f-6b64f6e0da73
# ╠═5b9d18dc-3e19-11eb-03e9-9f231903bd84
# ╠═d091d5e2-357f-11eb-385b-252f9ee49070
# ╠═ed7ac13e-357f-11eb-170b-31a27207af5f
# ╠═293aad98-3587-11eb-0f56-1d8144ad7e84
# ╠═a002f77c-3580-11eb-0ad8-e946d85c84c7
# ╠═092d49d4-3584-11eb-226b-bde1f2e49a22
# ╠═24a21870-360b-11eb-1269-db94fecdb0a6
# ╠═c6232b50-360b-11eb-18a2-39bdc25fb03b
# ╠═cff6fad6-360b-11eb-3e9b-a7cf6a270f8f
# ╠═d1b49f7e-360b-11eb-2b4d-b5a6ab46505e
# ╠═d34046d6-360b-11eb-31cd-6378f8c1729c
# ╠═d46c5e3c-360b-11eb-3ab7-9dc5eeb107d6
# ╠═0282c34c-3580-11eb-28c5-e5badd2c345f
# ╠═6b97b4f0-3580-11eb-28e5-b356737b0905
# ╠═3cf1f458-3a1c-11eb-2d51-a70a21c10295
# ╠═49e8abac-3e18-11eb-28ca-f9af0718950d
# ╠═219e21a4-3e1d-11eb-2a02-fd152e843650
# ╠═f2dc08a6-3a1e-11eb-08b3-81a2ce43c86a
# ╠═99fb92e4-3e1d-11eb-3120-7b09e7d9a257
# ╠═5d9312be-3e1d-11eb-184e-6fc51d067282
# ╠═c6073d4a-3e1d-11eb-3262-df23bbe50cea
# ╠═c60af316-3e1d-11eb-238c-d5ef097d9875
# ╟─af61e62c-3e24-11eb-38ec-57b4fc56b734
# ╠═8357b576-3e23-11eb-2198-b70b086ce536
# ╠═c6168438-3e1d-11eb-293e-f7115be86ef0
# ╠═c6173aca-3e1d-11eb-38d8-db7ac755d1e5
# ╠═c62ad834-3e1d-11eb-02ca-537556743757
# ╠═c62c56fa-3e1d-11eb-2312-8d30f6aab8c8
# ╠═c64c98d4-3e1d-11eb-2e66-13d6365eaff7
