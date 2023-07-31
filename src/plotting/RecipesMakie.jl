# https://github.com/SciML/SciMLBase.jl/issues/427
# https://github.com/VarLad/SciMLMakie.jl
function GLMakie.convert_arguments(::PointBased, contres::AbstractBranchResult, vars = nothing)
	ind1, ind2 = getPlotVars(contres, vars)
	return ([Point2f0(i, j) for (i, j) in zip(getproperty(contres.branch, ind1), getproperty(contres.branch, ind2))],)
end

function plot!(ax1, contres::AbstractBranchResult;
				plotfold = false,
				plotstability = true,
				plotspecialpoints = true,
				putspecialptlegend = true,
				filterspecialpoints = false,
				linewidthunstable = 1.0,
				linewidthstable = 3.0linewidthunstable,
				plotcirclesbif = true,
				applytoY = identity,
				applytoX = identity)
	
	# names for axis labels
	ind1, ind2 = getPlotVars(contres, nothing)
	xlab, ylab = getAxisLabels(ind1, ind2, contres)
	
	# stability linewidth
	linewidth = linewidthunstable
	if hasstability(contres) && plotstability
		linewidth = map(x -> isodd(x) ? linewidthstable : linewidthunstable, contres.stable)
	end
	lines!(ax1, contres, linewidth = linewidth)

	# display bifurcation points
	bifpt = filter(x -> (x.type != :none) && (x.type != :endpoint) && (plotfold || x.type != :fold) && (x.idx <= length(contres)-1), contres.specialpoint)
	if length(bifpt) >= 1 && plotspecialpoints #&& (ind1 == :param)
		if filterspecialpoints == true
			bifpt = filterBifurcations(bifpt)
		end
		scatter!(ax1, 
			map(x -> getproperty(x, ind1), bifpt), 
			map(x -> getproperty(x.printsol, ind2), bifpt);
			marker = map(x -> (x.status == :guess) && (plotcirclesbif==false) ? :rect : :circle, bifpt), 
			markersize = 10, 
			color = map(x -> colorbif[x.type], bifpt),
			)
	end

	# add legend for bifurcation points
	if putspecialptlegend && length(bifpt) >= 1
		bps = unique(x -> x.type, [pt for pt in bifpt if (pt.type != :none && (plotfold || pt.type != :fold))])
		(length(bps) == 0) && return
		for pt in bps
			scatter!(ax1, 
				[applytoX(getproperty(contres[pt.idx], ind1))], 
				[applytoY(getproperty(contres[pt.idx], ind2))];
				color = getColor(pt.type),
				markersize = 10,
				label = "$(pt.type)")
		end
		GLMakie.axislegend(ax1, merge = true, unique = true)
	end
	ax1
end

function plotBranchCont(contres::ContResult,
		sol::BorderedArray,
		contparms,
		plotuserfunction;
		plotfold = false,
		plotstability = true,
		plotspecialpoints = true,
		putspecialptlegend = true,
		filterspecialpoints = false,
		linewidthunstable = 1.0,
		linewidthstable = 3.0linewidthunstable,
		plotcirclesbif = true,
		applytoY = identity,
		applytoX = identity)

	if length(contres) == 0; return ; end

	# names for axis labels
	ind1, ind2 = getPlotVars(contres, nothing)
	xlab, ylab = getAxisLabels(ind1, ind2, contres)

	# stability linewidth
	linewidth = linewidthunstable
	if hasstability(contres) && plotstability
		linewidth = map(x -> isodd(x) ? linewidthstable : linewidthunstable, contres.stable)
	end

	fig = Figure(resolution = (1200, 700))
	ax1 = fig[1:2, 1] = Axis(fig, xlabel = String(xlab), ylabel = String(ylab), tellheight = true)

	ax2 = fig[1, 2] = Axis(fig, xlabel = "step", ylabel = String(xlab))
	lines!(ax2, contres.step, contres.param, linewidth = linewidth)

	if computeEigenElements(contparms)
		eigvals = contres.eig[end].eigenvals
		ax_ev = fig[3, 1:2] = Axis(fig, xlabel = "Re", ylabel = "Im")
		scatter!(ax_ev, real.(eigvals), imag.(eigvals), markerstrokewidth = 0, markersize = 10, color = :black)
		# add stability boundary
		maxIm = maximum(imag, eigvals)
		minIm = minimum(imag, eigvals)
		if maxIm-minIm < 1e-6
			maxIm, minIm = 1, -1
		end
		lines!(ax_ev, [0, 0], [maxIm, minIm], color = :blue, linewidth = linewidthunstable)
	end

	# plot arrow to indicate the order of computation
	if length(contres) > 1
		x = contres.branch[end].param
		y = getproperty(contres.branch,1)[end]
		u = contres.branch[end].param - contres.branch[end-1].param
		v = getproperty(contres.branch,1)[end]-getproperty(contres.branch,1)[end-1]
		GLMakie.arrows!(ax1, [x], [y], [u], [v], color = :green, arrowsize = 20,)
	end

	plot!(ax1, contres; plotfold, plotstability, plotspecialpoints, putspecialptlegend, filterspecialpoints, linewidthunstable, linewidthstable, plotcirclesbif, applytoY, applytoX)

	if isnothing(plotuserfunction) == false
		ax_perso = fig[2, 2] = Axis(fig, tellheight = true)
		plotuserfunction(ax_perso, sol.u, sol.p; ax1 = ax1)
	end

	display(fig)
	fig
end

function plot(contres::AbstractBranchResult; 
		kP...)
	if length(contres) == 0; return ;end

	ind1, ind2 = getPlotVars(contres, nothing)
	xlab, ylab = getAxisLabels(ind1, ind2, contres)

	fig = Figure(resolution = (1200, 700))
	ax1 = fig[1, 1] = Axis(fig, xlabel = String(xlab), ylabel = String(ylab), tellheight = true)
	
	plot!(ax1, contres; kP...)

	display(fig)
	fig
end

function plot(contresV::AbstractBranchResult...; kP...)
	if length(contresV) == 0; return ;end
	fig = Figure(resolution = (1200, 700))
	ax1 = fig[1, 1] = Axis(fig)

	for (id, contres) in pairs(contresV)

		ind1, ind2 = getPlotVars(contres, nothing)
		xlab, ylab = getAxisLabels(ind1, ind2, contres)

		plot!(ax1, contres; kP...)

	end
	GLMakie.axislegend(ax1, merge = true, unique = true)

	display(fig)
	fig
end

####################################################################################################
# plotting function of the periodic orbits
# function plotPeriodicPOTrap(x, M, Nx, Ny; ratio = 2, kwargs...)
# 	@assert ratio > 0 "You need at least one component"
# 	n = Nx*Ny
# 	outpo = reshape(x[1:end-1], ratio * n, M)
# 	po = reshape(x[1:n,1], Nx, Ny)
# 	rg = 2:6:M
# 	for ii in rg
# 		po = hcat(po, reshape(outpo[1:n,ii], Nx, Ny))
# 	end
# 	heatmap!(po; color = :viridis, fill=true, xlabel = "space", ylabel = "space", kwargs...)
# 	for ii in 1:length(rg)
# 		plot!([ii*Ny, ii*Ny], [1, Nx]; color = :red, width = 3, label = "", kwargs...)
# 	end
# end

function plotPeriodicPOTrap(outpof, n, M; ratio = 2)
	@assert ratio > 0 "You need at least one component"
	outpo = reshape(outpof[1:end-1], ratio * n, M)
	if ratio == 1
		heatmap(outpo[1:n,:]', ylabel="Time", color=:viridis)
	else
		fig = GLMakie.Figure()
		ax1 = Axis(fig[1,1], ylabel="Time")
		ax2 = Axis(fig[1,2], ylabel="Time")
		# GLMakie.heatmap!(ax1, rand(2,2))
		GLMakie.heatmap!(ax1, outpo[1:n,:]')
		GLMakie.heatmap!(ax2, outpo[n+2:end,:]')
		fig
	end
end
####################################################################################################
# function plotPeriodicShooting!(x, M; kwargs...)
# 	N = div(length(x), M);	plot!(x; label = "", kwargs...)
# 	for ii in 1:M
# 		plot!([ii*N, ii*N], [minimum(x), maximum(x)] ;color = :red, label = "", kwargs...)
# 	end
# end

# function plotPeriodicShooting(x, M; kwargs...)
# 	plot();plotPeriodicShooting!(x, M; kwargs...)
# end
####################################################################################################
# plot recipes for the bifurcation diagram
function plot(bd::BifDiagNode; code = (), level = (-Inf, Inf))
	if ~hasbranch(bd); return; end

	fig = Figure(resolution = (1200, 700))
	ax = fig[1, 1] = Axis(fig)

	_plot_bifdiag_makie!(ax, bd; code, level)

	display(fig)
	fig
end

function _plot_bifdiag_makie!(ax, bd::BifDiagNode; code = (), level = (-Inf, Inf))
	if ~hasbranch(bd); return; end

	_bd = getBranch(bd, code)
	_plot_bifdiag_makie!(ax, _bd.child; code = (), level = level)

	# !! plot root branch in last so the bifurcation points do not alias, for example a 2d BP would be plot as a 1d BP if the order were reversed
	if level[1] <= _bd.level <= level[2]
		plot!(ax, _bd.γ)
	end
end

function _plot_bifdiag_makie!(ax, bd::Vector{BifDiagNode}; code = (), level = (-Inf, Inf))
	for b in bd
		_plot_bifdiag_makie!(ax, b; code, level )
	end
end