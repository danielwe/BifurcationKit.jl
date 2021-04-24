# using Revise
using Test

@testset verbose = true "BifurcationKit" begin

	@testset "Linear Solvers" begin
		include("precond.jl")
		include("test_linear.jl")
	end

	@testset "Newton" begin
		include("test_newton.jl")
		include("test-bordered-problem.jl")
	end
	
	@testset "Continuation" begin
		include("test_bif_detection.jl")
		include("test-cont-non-vector.jl")
		include("simple_continuation.jl")
		include("testNF.jl")
	end
	
	@testset "Fold Codim 2" begin
		include("testJacobianFoldDeflation.jl")
	end

	@testset "Hopf Codim 2" begin
		include("testHopfMA.jl")
	end

	@testset "Periodic orbits" begin
		include("test_potrap.jl")
		include("test_SS.jl")
		include("poincareMap.jl")
		include("stuartLandauSH.jl")
		include("stuartLandauTrap.jl")
	end
end