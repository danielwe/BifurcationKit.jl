using BlockArrays, SparseArrays, Setfield
####################################################################################################
# method using the Trapezoidal rule (Order 2 in time) and discretisation of the periodic orbit.

"""
	pb = PeriodicOrbitTrapProblem(F, J, ϕ, xπ, M::Int)
This composite type implements Finite Differences based on a Trapezoidal rule to locate periodic orbits. The arguments are as follows
- `F` vector field
- `J` jacobian of `F`
- `d2F = nothing` Hessian of F (optional), useful for continuation of Fold of periodic orbits
- `ϕ` used to set a section for the phase constraint equation
- `xπ` used in the section for the phase constraint equation
- `M::Int` number of time slices
- `linsolver: = DefaultLS()` linear solver for each time slice, i.e. to solve `J⋅sol = rhs`. This is only used for the computation of the Floquet multipliers.
- `isinplace::Bool` whether `F` and `J` are inplace functions (Experimental). In this case, the functions `F` and `J` must have the following definitions `(o, x) ->  F(o, x)` and `(o, x, dx) -> J(o, x, dx)`.
- `ongpu::Bool` whether the computation takes place on the gpu (Experimental)

You can then call `pb(orbitguess)` to compute the functional on a `orbitguess`. Note that `orbitguess` must be of size M * N + 1 where N is the number of unknowns in the state space and `orbitguess[M*N+1]` is an estimate of the period of the limit cycle.

The scheme is as follows, one look for `T = x[end]` and

 ``\\left(x_{i} - x_{i-1}\\right) - \\frac{h}{2} \\left(F(x_{i}) + F(x_{i-1})\\right) = 0,\\ i=1,\\cdots,m-1``

with ``u_{0} := u_{m-1}`` and the periodicity condition ``u_{m} - u_{1} = 0`` and

where `h = T/M`. Finally, the phase of the periodic orbit is constrained by using a section

 ``\\langle x[1] - x_\\pi, \\phi\\rangle=0.``

 A functional, hereby called `G`, encodes this problem. The following methods are available

- `pb(orbitguess)` evaluates the functional G on `orbitguess`
- `pb(orbitguess, du)` evaluates the jacobian `dG(orbitguess).du` functional at `orbitguess` on `du`
- `pb(Val(:JacFullSparse), orbitguess)` return the sparse matrix of the jacobian `dG(orbitguess)` at `orbitguess` without the constraints. It is called `A_γ` in the docs.
- `pb(Val(:JacFullSparseInplace), J, orbitguess)`. Same as `pb(Val(:JacFullSparse), orbitguess)` but overwrites `J` inplace. Note that the sparsity pattern must be the same independantly of the values of the parameters or of `orbitguess`. In some cases, this is significantly faster than `pb(Val(:JacFullSparse), orbitguess)`.
- `pb(Val(:JacCyclicSparse), orbitguess)` return the sparse cyclic matrix Jc (see the docs) of the jacobian `dG(orbitguess)` at `orbitguess`
- `pb(Val(:BlockDiagSparse), orbitguess)` return the diagonal of the sparse matrix of the jacobian `dG(orbitguess)` at `orbitguess`. This allows to design Jacobi preconditioner. Use `blockdiag`.

!!! note "GPU call"
    For these methods to work on the GPU, for example with `CuArrays` in mode `allowscalar(false)`, we face the issue that the function `extractPeriodFDTrap` won't be well defined because it is a scalar operation. One may have to redefine it like `extractPeriodFDTrap(x::CuArray) = x[end:end]` or something else. Also, note that you must pass the option `ongpu = true` for the functional to be evaluated efficiently on the gpu.

"""
@with_kw struct PeriodicOrbitTrapProblem{TF, TJ, TJt, Td2F, vectype, Tls <: AbstractLinearSolver}
	# Function F(x, p) = 0
	F::TF

	# Jacobian of F wrt x
	J::TJ

	# Jacobian transpose of F wrt x. This is mainly used for matrix-free computation of Folds of limit cycles
	Jt::TJt = nothing

	# Hessian of F wrt x, useful for continuation of Fold of periodic orbits
	d2F::Td2F = nothing

	# variables to define a Section for the phase constraint equation
	ϕ::vectype
	xπ::vectype

	# discretisation of the time interval
	M::Int = 1

	# dimension of the problem in case of an AbstractVector
	N::Int = 0

	# linear solver for each slice, i.e. to solve J⋅sol = rhs. This is mainly used for the computation of the Floquet coefficients
	linsolver::Tls = DefaultLS()

	# whether F and J are inplace functions
	isinplace::Bool = false

	# whether the computation takes place on the gpu
	ongpu::Bool = false
end

isinplace(pb::PeriodicOrbitTrapProblem) = pb.isinplace
ongpu(pb::PeriodicOrbitTrapProblem) = pb.ongpu

function applyF(pb::PeriodicOrbitTrapProblem, dest, x)
	if isinplace(pb)
		pb.F(dest, x)
	else
		dest .= pb.F(x)
	end
	dest
end

function applyJ(pb::PeriodicOrbitTrapProblem, dest, x, dx)
	if isinplace(pb)
		pb.J(dest, x, dx)
	else
		dest .= apply(pb.J(x), dx)
	end
	dest
end

function PeriodicOrbitTrapProblem(F::TF, J::TJ, ϕ::vectype, xπ::vectype, M, ls::AbstractLinearSolver = DefaultLS(); isinplace = false, ongpu = false) where {TF, TJ, vectype}
	_length = ϕ isa AbstractVector ? length(ϕ) : 0
	return PeriodicOrbitTrapProblem{TF, TJ, Nothing, Nothing, vectype, typeof(ls)}(F = F, J = J, ϕ = ϕ, xπ = xπ, M = M, N = _length, linsolver = ls, isinplace = isinplace, ongpu = ongpu)
end

function PeriodicOrbitTrapProblem(F::TF, J::TJ, d2F::Td2f, ϕ::vectype, xπ::vectype, M, ls::AbstractLinearSolver = DefaultLS(); isinplace = false, ongpu = false) where {TF, TJ, Td2f, vectype}
	_length = ϕ isa AbstractVector ? length(ϕ) : 0
	return PeriodicOrbitTrapProblem{TF, TJ, Nothing, Td2f, vectype, typeof(ls)}(F = F, J = J, d2F = d2F, ϕ = ϕ, xπ = xπ, M = M, N = _length, linsolver = ls, isinplace = isinplace, ongpu = ongpu)
end

# these functions extract the last component of the periodic orbit guess
extractPeriodFDTrap(x::AbstractVector) = x[end]
extractPeriodFDTrap(x::BorderedArray)  = x.T

# these functions extract the time slices components
extractTimeSlice(x::AbstractVector, N, M) = @views reshape(x[1:end-1], N, M)
extractTimeSlice(x::BorderedArray,  N, M) = x.u

function POTrapScheme!(pb::PeriodicOrbitTrapProblem, dest, u1, u2, h, tmp, linear::Bool = true)
	# this function implements the basic implicit scheme used for the time integration
	# because this function is called in a cyclic manner, we save in tmp the value F(u2) in order to avoid recomputing it in a subsequent call
	# basically tmp is F(u2)
	if linear
		dest .= tmp
		# tmp <- pb.F(u1)
		applyF(pb, tmp, u1) #TODO this line does not almost seem to be type stable in code_wartype, gives @_11::Union{Nothing, Tuple{Int64,Int64}}
		dest .= u1 .- u2 .- h .* (dest .+ tmp)
	else
		dest .-= h .* tmp
		# tmp <- pb.F(u1)
		applyF(pb, tmp, u1)
		dest .-= h .* tmp
	end
end

function POTrapSchemeJac!(pb::PeriodicOrbitTrapProblem, dest, u1, u2, du1, du2, h, tmp)
	# this function implements the basic implicit scheme used for the time integration
	# useful for the matrix-free jacobian
	# basically tmp is dF(u2).du2 (see above for explanation)
	dest .= tmp
	# tmp <- apply(pb.J(u1), du1)
	applyJ(pb, tmp, u1, du1)
	dest .= du1 .- du2 .- h .* (dest .+ tmp)
end

"""
This function implements the functional for finding periodic orbits based on finite differences using the Trapezoidal rule. It works for inplace / out of place vector fields pb.F
"""
function POTrapFunctional!(pb::PeriodicOrbitTrapProblem, out, u0)
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M

	u0c  = extractTimeSlice(u0, N, M)
	outc = extractTimeSlice(out, N, M)

	# outc[:, M] plays the role of tmp until it is used just after the for-loop
	@views applyF(pb, outc[:, M], u0c[:, M-1])

	@views POTrapScheme!(pb, outc[:, 1], u0c[:, 1], u0c[:, M-1], h/2, outc[:, M])

	for ii = 2:M-1
		# this function avoids computing F(u0c[:, ii]) twice
		@views POTrapScheme!(pb, outc[:, ii], u0c[:, ii], u0c[:, ii-1], h/2, outc[:, M])
	end

	# closure condition ensuring a periodic orbit
	outc[:, M] .= @views u0c[:, M] .- u0c[:, 1]

	# this is for CuArrays.jl to work in the mode allowscalar(false)
	if ongpu(pb)
		return @views vcat(out[1:end-1], dot(u0c[:, 1], pb.ϕ) - dot(pb.xπ, pb.ϕ)) # this is the phase condition
	else
		out[end] = @views dot(u0c[:, 1], pb.ϕ) - dot(pb.xπ, pb.ϕ) #dot(u0c[:, 1] .- pb.xπ, pb.ϕ)
		return out
	end
end

"""
Matrix free expression of the Jacobian of the problem for computing periodic obits when evaluated at `u0` and applied to `du`.
"""
function POTrapFunctionalJac!(pb::PeriodicOrbitTrapProblem, out, u0, du)
	M = pb.M
	N = pb.N
	T  = extractPeriodFDTrap(u0)
	dT = extractPeriodFDTrap(du)
	h = T / M

	u0c = extractTimeSlice(u0, N, M)
	outc = extractTimeSlice(out, N, M)
	duc = extractTimeSlice(du, N, M)

	# compute the cyclic part
	@views Jc(pb, outc, u0[1:end-1-N], h, du[1:end-N-1], outc[:, M])

	# outc[:, M] plays the role of tmp until it is used just after the for-loop
	tmp = @view outc[:, M]

	# we now compute the partial derivative w.r.t. the period T
	# the .+ is for the GPU
	# out .+= @views (pb(vcat(u0[1:end-1], T .+ δ)) .- pb(u0)) ./ δ .* dT
	@views applyF(pb, tmp, u0c[:, M-1])

	@views POTrapScheme!(pb, outc[:, 1], u0c[:, 1], u0c[:, M-1], dT / (2M), tmp, false)
	for ii = 2:M-1
		@views POTrapScheme!(pb, outc[:, ii], u0c[:, ii], u0c[:, ii-1], dT / (2M), tmp, false)
	end

	# closure condition ensuring a periodic orbit
	outc[:, M] .= @views duc[:, M] .- duc[:, 1]

	# this is for CuArrays.jl to work in the mode allowscalar(false)
	if ongpu(pb)
		return @views vcat(out[1:end-1], dot(duc[:, 1], pb.ϕ))
	else
		out[end] = @views dot(duc[:, 1], pb.ϕ)
		return out
	end
end

function (pb::PeriodicOrbitTrapProblem)(u0::AbstractVector)
	out = similar(u0)
	POTrapFunctional!(pb, out, u0)
end

function (pb::PeriodicOrbitTrapProblem)(u0::AbstractVector, du)
	out = similar(du)
	POTrapFunctionalJac!(pb, out, u0, du)
end

# function (pb::PeriodicOrbitTrapProblem)(out, u0::AbstractVector, du)
# 	# out = similar(du)
# 	POTrapFunctionalJac!(pb, out, u0, du)
# end
####################################################################################################
# Matrix free expressions of matrices related to the Jacobian Matrix of the PO functional
"""
Function to compute the Matrix-Free version of Aγ, see docs for its expression.
"""
function Agamma!(pb::PeriodicOrbitTrapProblem, outc, u0::vectype, du) where {vectype <: AbstractVector}
	# u0 of size N * M + 1
	# du of size N * M
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M

	u0c = extractTimeSlice(u0, N, M)

	# compute the cyclic part
	@views Jc(pb, outc, u0[1:end-1-N], h, du[1:end-N], outc[:, M])

	# closure condition ensuring a periodic orbit
	duc = reshape(du, N, M)
	outc[:, M] .= @views duc[:, M] .- duc[:, 1]
	return nothing
end

"""
Function to compute the Matrix-Free version of the cyclic matrix Jc, see docs for its expression.
"""
function Jc(pb::PeriodicOrbitTrapProblem, outc::AbstractMatrix, u0::vectype, h, du, tmp)  where {vectype <: AbstractVector}
	# tmp plays the role of buffer array
	# u0 of size N * (M - 1)
	# du of size N * (M - 1)
	# outc of size N * M
	# h = T / M
	M = pb.M
	N = pb.N

	u0c = reshape(u0, N, M-1)
	duc = reshape(du, N, M-1)

	@views applyJ(pb, tmp, u0c[:, M-1], duc[:, M-1])

	@views POTrapSchemeJac!(pb, outc[:, 1], u0c[:, 1], u0c[:, M-1],
											duc[:, 1], duc[:, M-1], h/2, tmp)

	for ii = 2:M-1
		@views POTrapSchemeJac!(pb, outc[:, ii], u0c[:, ii], u0c[:, ii-1],
												 duc[:, ii], duc[:, ii-1], h/2, tmp)
	end

	return vec(outc)
end

function Jc(pb::PeriodicOrbitTrapProblem, u0, du)
	M = pb.M
	N = pb.N

	T = extractPeriodFDTrap(u0)
	h = T / M

	out  = similar(du)
	outc = reshape(out, N, M-1)
	tmp = similar(view(outc, :, 1))
	return @views Jc(pb, outc, u0[1:end-1-N], h, du, tmp)
end
####################################################################################################
"""
Matrix by blocks expression of the Jacobian for the PO functional computed at the space-time guess: `u0`
"""
function jacobianPOFD_block(pb::PeriodicOrbitTrapProblem, u0::vectype; γ = 1.0) where {vectype <: AbstractVector}
	# extraction of various constants
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M

	Aγ = BlockArray(spzeros(M * N, M * N), N * ones(Int64, M),  N * ones(Int64, M))
	cylicPOFD_block!(pb, u0, Aγ)

	In = spdiagm( 0 => ones(N))
	setblock!(Aγ, -γ * In, M, 1)
	setblock!(Aγ,  In,     M, M)
	return Aγ
end

"""
This function populates Jc with the cyclic matrix using the different Jacobians
"""
function cylicPOFD_block!(pb::PeriodicOrbitTrapProblem, u0::vectype, Jc::BlockArray) where {vectype <: AbstractVector}
	# extraction of various constants
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M

	In = spdiagm( 0 => ones(N))
	On = spzeros(N, N)

	u0c = extractTimeSlice(u0, N, M)
	outc = similar(u0c)

	tmpJ = @views pb.J(u0c[:, 1])

	@views Jn = In - h/2 .* tmpJ
	setblock!(Jc, Jn, 1, 1)

	@views Jn = -In - h/2 .* pb.J(u0c[:, M-1])
	setblock!(Jc, Jn, 1, M-1)

	for ii=2:M-1
		@views Jn = -In - h/2 .* tmpJ
		setblock!(Jc, Jn, ii, ii-1)

		tmpJ .= @views pb.J(u0c[:, ii])

		@views Jn = In - h/2 .* tmpJ
		setblock!(Jc, Jn, ii, ii)
	end
	return Jc
end

function cylicPOFD_block(pb::PeriodicOrbitTrapProblem, u0::vectype) where {vectype <: AbstractVector}
	# extraction of various constants
	M = pb.M
	N = pb.N
	Jc = BlockArray(spzeros((M - 1) * N, (M - 1) * N), N * ones(Int64, M-1),  N * ones(Int64, M-1))
	cylicPOFD_block!(pb, u0, Jc)
end

cylicPOFD_sparse(pb::PeriodicOrbitTrapProblem, orbitguess0) = blockToSparse(cylicPOFD_block(pb, orbitguess0))

"""
This method returns the jacobian of the functional G encoded in PeriodicOrbitTrapProblem using a Sparse representation.
"""
function (pb::PeriodicOrbitTrapProblem{TF, TJ, TJt, Td2F, vectype, Tls})(::Val{:JacFullSparse}, u0::vectype; γ = 1.0, δ = 1e-9) where {TF, TJ, TJt, Td2F, vectype <: AbstractVector, Tls}
	# extraction of various constants
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M
	Aγ_block = jacobianPOFD_block(pb, u0; γ = γ)

	# we now set up the last line / column
	@views ∂TGpo = (pb(vcat(u0[1:end-1], T + δ)) .- pb(u0)) ./ δ

	# this is bad for performance. Get converted to SparseMatrix at the next line
	Aγ = blockToSparse(Aγ_block) # most of the computing time is here!!
	@views Aγ = hcat(Aγ, ∂TGpo[1:end-1])
	Aγ = vcat(Aγ, spzeros(1, N * M + 1))

	Aγ[N*M+1, 1:N] .=  pb.ϕ
	Aγ[N*M+1, N*M+1] = ∂TGpo[end]
	return Aγ
end

"""
This method returns the jacobian of the functional G encoded in PeriodicOrbitTrapProblem using a Sparse representation and inplace update.
"""
@views function (pb::PeriodicOrbitTrapProblem{TF, TJ, TJt, Td2F, vectype, Tls})(::Val{:JacFullSparseInplace}, J0, u0::vectype; γ = 1.0, δ = 1e-9) where {TF, TJ, TJt, Td2F, vectype <: AbstractVector, Tls}
		# update J0 inplace assuming that the sparsity pattern of J0 and dG(orbitguess0) are the same
		M = pb.M
		N = pb.N
		T = extractPeriodFDTrap(u0)
		h = T / M
		In = spdiagm( 0 => ones(N))
		On = spzeros(N, N)

		u0c = extractTimeSlice(u0, N, M)
		outc = similar(u0c)

		tmpJ = @views pb.J(u0c[:, 1])

		Jn = In - h/2 * tmpJ
		# setblock!(Jc, Jn, 1, 1)
		J0[1:N, 1:N] .= Jn

		Jn = -In - h/2 * pb.J(u0c[:, M-1])
		# setblock!(Jc, Jn, 1, M-1)
		J0[1:N, (M-2)*N+1:(M-1)*N] .= Jn

		for ii=2:M-1
			Jn = -In - h/2 * tmpJ
			# the next lines cost the most
			# setblock!(Jc, Jn, ii, ii-1)
			J0[(ii-1)*N+1:(ii)*N, (ii-2)*N+1:(ii-1)*N] .= Jn

			tmpJ = pb.J(u0c[:, ii])

			Jn = In - h/2 * tmpJ
			# setblock!(Jc, Jn, ii, ii)
			J0[(ii-1)*N+1:(ii)*N, (ii-1)*N+1:(ii)*N] .= Jn
		end

		# setblock!(Aγ, -γ * In, M, 1)
		# useless to update:
			# J0[(M-1)*N+1:(M)*N, (1-1)*N+1:(1)*N] .= -In
		# setblock!(Aγ,  In,     M, M)
		# useless to update:
			# J0[(M-1)*N+1:(M)*N, (M-1)*N+1:(M)*N] .= In

		# we now set up the last line / column
		∂TGpo = (pb(vcat(u0[1:end-1], T + δ)) .- pb(u0)) ./ δ
		J0[:, end] .=  ∂TGpo

		# this following does not depend on u0, so it does not change
		# J0[N*M+1, 1:N] .=  pb.ϕ

		return J0
end


@views function (pb::PeriodicOrbitTrapProblem{TF, TJ, TJt, Td2F, vectype, Tls})(::Val{:JacFullSparseInplace}, J0, u0::vectype, indx; γ = 1.0, δ = 1e-9) where {TF, TJ, TJt, Td2F, vectype <: AbstractVector, Tls}
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M
	In = spdiagm( 0 => ones(N))
	On = spzeros(N, N)

	u0c = extractTimeSlice(u0, N, M)
	outc = similar(u0c)

	tmpJ = pb.J(u0c[:, 1])

	Jn = In - tmpJ * (h/2)
	# setblock!(Jc, Jn, 1, 1)
	J0.nzval[indx[1,1]] .= Jn.nzval

	Jn = -In - pb.J(u0c[:, M-1]) * (h/2)
	# setblock!(Jc, Jn, 1, M-1)
	J0.nzval[indx[1,M-1]] .= Jn.nzval

	for ii=2:M-1
		Jn = -In - tmpJ * (h/2)
		# the next lines cost the most
		# setblock!(Jc, Jn, ii, ii-1)
		J0.nzval[indx[ii,ii-1]] .= Jn.nzval

		tmpJ = pb.J(u0c[:, ii])# * (h/2)

		Jn = In -  tmpJ * (h/2)
		# setblock!(Jc, Jn, ii, ii)
		J0.nzval[indx[ii,ii]] .= Jn.nzval
	end

	# setblock!(Aγ, -γ * In, M, 1)
	# useless to update:
		# J0[(M-1)*N+1:(M)*N, (1-1)*N+1:(1)*N] .= -In
	# setblock!(Aγ,  In,     M, M)
	# useless to update:
		# J0[(M-1)*N+1:(M)*N, (M-1)*N+1:(M)*N] .= In

	# we now set up the last line / column
	∂TGpo = (pb(vcat(u0[1:end-1], T + δ)) .- pb(u0)) ./ δ
	J0[:, end] .=  ∂TGpo

	# this following does not depend on u0, so it does not change
	# J0[N*M+1, 1:N] .=  pb.ϕ

	return J0
end

function (pb::PeriodicOrbitTrapProblem{TF, TJ, TJt, Td2F, vectype, Tls})(::Val{:JacCyclicSparse}, u0::vectype, γ = 1.0) where {TF, TJ, TJt, Td2F, vectype <: AbstractVector, Tls}
	# extraction of various constants
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M
	Aγ_block = jacobianPOFD_block(pb, u0; γ = γ)

	# this is bad for performance. Get converted to SparseMatrix at the next line
	Aγ = blockToSparse(Aγ_block) # most of the computing time is here!!
	return Aγ[1:end-N, 1:end-N]
end

function (pb::PeriodicOrbitTrapProblem{TF, TJ, TJt, Td2F, vectype, Tls})(::Val{:BlockDiagSparse}, u0::vectype) where {TF, TJ, TJt, Td2F, vectype <: AbstractVector, Tls}
	# extraction of various constants
	M = pb.M
	N = pb.N
	T = extractPeriodFDTrap(u0)
	h = T / M
	A_diag_block = BlockArray(spzeros(M * N, M * N), N * ones(Int64, M),  N * ones(Int64, M))

	In = spdiagm( 0 => ones(N))

	u0c = reshape(u0[1:end-1], N, M)
	outc = similar(u0c)

	@views Jn = In - h/2 .* pb.J(u0c[:, 1])
	setblock!(A_diag_block, Jn, 1, 1)

	for ii=2:M-1
		@views Jn = In - h/2 .* pb.J(u0c[:, ii])
		setblock!(A_diag_block, Jn, ii, ii)
	end
	setblock!(A_diag_block, In, M, M)

	A_diag_sp = blockToSparse(A_diag_block) # most of the computing time is here!!
	return A_diag_sp
end
####################################################################################################
# The following struct encodes a jacobian of PeriodicOrbitTrapProblem which is a convenient composite type for the computation of Floquet multipliers. Therefore, it is only used in the method continuationPOTrap
mutable struct PeriodicOrbitTrapJacobianFull{Tpb, Tj, vectype}
	pb::Tpb								# PeriodicOrbitTrapProblem
	J::Tj								# jacobian of the problem
	orbitguess0::vectype				# point at which the jacobian is computed
end

# computation of the jacobian, nothing to be done
(pojacfull::PeriodicOrbitTrapJacobianFull)(x) = return pojacfull

# linear solver for the PO functional, akin to a bordered linear solver
@with_kw mutable struct PeriodicOrbitTrapLS{Tl} <: AbstractLinearSolver
	linsolver::Tl = DefaultLS()			# linear solver
end

# linear solver for the jacobian
(pols::PeriodicOrbitTrapLS)(pojacfull::PeriodicOrbitTrapJacobianFull, rhs) = pols.linsolver(pojacfull.J, rhs)

(pols::PeriodicOrbitTrapLS)(pojacfull::PeriodicOrbitTrapJacobianFull, rhs1, rhs2) = pols.linsolver(pojacfull.J, rhs1, rhs2)

####################################################################################################
# Linear solvers of the linearized version of the functional G implemented by PeriodicOrbitTrapProblem

# composite type to encode the Aγ Operator and its associated cyclic matrix
@with_kw mutable struct AγOperator{Tvec, Tjc, T, Tpb}
	N::Int64 = 0				    		# dimension of a time slice
	orbitguess::Tvec = zeros(1)				# point at which Aγ is evaluated, of size N * M + 1
	Jc::Tjc	= lu(spdiagm(0 => ones(1)))	    # lu factorisation of the cyclic matrix
	is_matrix_free::Bool = false	    	# whether we consider a sparse matrix representation or a Matrix Free one
	γ::T = 1.0				    			# factor γ can be used to compute Floquet multipliers
	prob::Tpb = nothing						# PO functional, used when is_matrix_free = true
end

ismatrixfree(A::AγOperator) = A.is_matrix_free

# linear solver designed specifically to deal with AγOperator
@with_kw struct AγLinearSolver{Tls} <: AbstractLinearSolver
	# Linear solver to invert the cyclic matrix Jc contained in Aγ
	linsolver::Tls = DefaultLS()
end

# linear solver for the PO functional, akin to a bordered linear solver
@with_kw mutable struct PeriodicOrbitTrapBLS{Tl} <: AbstractLinearSolver
	linsolverbls::Tl = BorderingBLS(AγLinearSolver())	# linear solver
end

# The following structure encodes a jacobian of PeriodicOrbitTrapProblem which eases the use of PeriodicOrbitTrapBLS. It is made so that accessing to the cyclic matrix Jc or Aγ is easier. It is combined with a specific linear solver. It is also a convenient structure for the computation of Floquet multipliers. Therefore, it is only used in the method continuationPOTrap
@with_kw mutable struct PeriodicOrbitTrapJacobianBordered{Tpb, T∂, vectype}
	pb::Tpb								# PeriodicOrbitTrapProblem
	∂TGpo::T∂	= nothing				# derivative of the PO functional G wrt T
	Aγ::AγOperator = AγOperator()		# Aγ Operator involved in the Jacobian of the PO functional
	orbitguess0::vectype = nothing		# point at which the jacobian is computed
end

# this function is called whenever the jacobian of G has to be updated
function (J::PeriodicOrbitTrapJacobianBordered)(orbitguess0::AbstractVector; δ = 1e-9)
	# u0 must be an orbit guess
	@views J.orbitguess0 .= orbitguess0[1:length(J.orbitguess0)]

	# we compute the derivative of the problem wrt the period TODO: remove this or improve!!
	T = extractPeriodFDTrap(orbitguess0)
	# TODO REMOVE CE vcat!
	@views J.∂TGpo .= (J.pb(vcat(orbitguess0[1:end-1], T + δ)) .- J.pb(orbitguess0)) ./ δ

	# update Aγ
	J.Aγ(J.pb, orbitguess0)

	# return J, needed to properly call the linear solver.
	return J
end


# function to update the cyclic matrix
function (A::AγOperator)(pb::PeriodicOrbitTrapProblem, orbitguess::AbstractVector)
	if ismatrixfree(A) == false
		# we store the lu decomposition of the newly computed cyclic matrix
		A.Jc = SparseArrays.lu(cylicPOFD_sparse(pb, orbitguess))
	else
		copyto!(A.orbitguess, orbitguess)
		A.prob = pb
	end
end

# this function is called whenever one wants to invert Aγ
function (ls::AγLinearSolver)(A::AγOperator, rhs)
	N = A.N
	if ismatrixfree(A) == false
		# we invert the cyclic part Jc of Aγ
		xbar, flag, numiter = @views ls.linsolver(A.Jc, rhs[1:end - N])
		!flag && @warn "Sparse solver for Aγ did not converge"
	else
		# we invert the cyclic part Jc of Aγ
		xbar, flag, numiter = @views ls.linsolver(dx -> Jc(A.prob, A.orbitguess, dx), rhs[1:end - N])
		!flag && @warn "Matrix Free solver for Aγ did not converge"
	end
	x = similar(rhs)
	x[1:end-N] .= xbar
	x[end-N+1:end] .= @views A.γ .* x[1:N] .+ rhs[end-N+1:end]
	return x ,flag, numiter
end

# Linear solver associated to PeriodicOrbitTrapJacobianBordered
function (ls::PeriodicOrbitTrapBLS)(J::PeriodicOrbitTrapJacobianBordered, rhs)
	N = J.pb.N

	# TODO REMOVE THIS HACK
	ϕ = zeros(length(rhs)-1)
	ϕ[1:N] .= J.pb.ϕ

	# we solve the bordered linear system as follows
	dX, dl, flag, liniter = @views ls.linsolverbls(J.Aγ, J.∂TGpo[1:end-1],
	 										 		  ϕ, J.∂TGpo[end],
													  rhs[1:end-1], rhs[end])

	return vcat(dX, dl), flag, sum(liniter)
end

# One could think that by implementing (ls::PeriodicOrbitTrapBLS)(J::PeriodicOrbitTrapJacobianBordered, rhs1, rhs2), we could speed up the computation of the linear Bordered system arising in the continuation process. However, we can note that this speed up would be observed only if a factorization of J.Aγ is available like an LU one. When such factorization is available, it is automatically stored as such in J.Aγ and so no speed up would be gained by implementing (ls::PeriodicOrbitTrapBLS)(J::PeriodicOrbitTrapJacobianBordered, rhs1, rhs2)
####################################################################################################
# newton wrappers
function _newton(probPO::PeriodicOrbitTrapProblem, orbitguess, options::NewtonPar, linearPO::Symbol = :BorderedLU; defOp::Union{Nothing, DeflationOperator{T, Tf, vectype}} = nothing, kwargs...) where {T, Tf, vectype}
	@assert linearPO in [:FullLU, :BorderedLU, :FullMatrixFree, :BorderedMatrixFree, :FullSparseInplace]
	N = probPO.N
	M = probPO.M

	if linearPO in [:FullLU, :FullMatrixFree, :FullSparseInplace]
		@assert orbitguess isa AbstractVector
		@assert length(orbitguess) == N * M + 1 "Error with size of the orbitguess"

		if linearPO == :FullLU
			jac = x -> probPO(Val(:JacFullSparse), x)
		elseif linearPO == :FullSparseInplace
			# sparse matrix to hold the jacobian
			_J =  probPO(Val(:JacFullSparse), orbitguess)
			_indx = getBlocks(_J, N, M)
			# inplace modification of the jacobian _J
			jac = x -> probPO(Val(:JacFullSparseInplace), _J, x)
		else
		 	jac = x -> ( dx -> probPO(x, dx))
		end

		if isnothing(defOp)
			return newton( x -> probPO(x), jac, orbitguess, options; kwargs...)
		else
			return newton( x -> probPO(x), jac, orbitguess, options, defOp; kwargs...)
		end

	else
		@assert orbitguess isa AbstractVector
		@assert length(orbitguess) == N * M + 1 "Error with size of the orbitguess"

		if linearPO == :BorderedLU
			Aγ = AγOperator(is_matrix_free = false, N = probPO.N, Jc = lu(spdiagm( 0 => ones(N * (M - 1)) )) )
			# linear solver
			lspo = PeriodicOrbitTrapBLS()
		else	# :BorderedMatrixFree
			Aγ = AγOperator(is_matrix_free = true, prob = probPO, N = probPO.N, orbitguess = zeros(N * M + 1), Jc = lu(spdiagm( 0 => ones(N * (M - 1)) ))  )
			# linear solver
			lspo = PeriodicOrbitTrapBLS(BorderingBLS(AγLinearSolver(options.linsolver)))
		end

		# create the jacobian
		JacPO = PeriodicOrbitTrapJacobianBordered(probPO, zeros(N * M + 1), Aγ, zeros(N * M + 1))

		if isnothing(defOp)
			return newton(x -> probPO(x), x ->  JacPO(x), orbitguess, (@set options.linsolver = lspo); kwargs...)
		else
			return newton(x -> probPO(x), x ->  JacPO(x), orbitguess, (@set options.linsolver = lspo), defOp; kwargs...)
		end
	end
end

"""
	newton(prob::PeriodicOrbitTrapProblem, orbitguess, options::NewtonPar, linearPO = :BorderedLU; kwargs...)

This is the Newton Solver for computing a periodic orbit using a functional G based on Finite Differences and a Trapezoidal rule.

# Arguments:
- `prob` a problem of type `PeriodicOrbitTrapProblem` encoding the functional G
- `orbitguess` a guess for the periodic orbit where `orbitguess[end]` is an estimate of the period of the orbit. It should be a vector of size `N * M + 1` where `M` is the number of time slices, `N` is the dimension of the phase space. This must be compatible with the numbers `N,M` in `prob`.
- `options` same as for the regular `newton` method
- `linearPO = :BorderedLU`. Specify the choice of the linear algorithm, which must belong to `[:FullLU, :FullSparseInplace, :BorderedLU, :FullMatrixFree, :BorderedMatrixFree, :FullSparseInplace]`. This is used to select a way of inverting the jacobian `dG` of the functional G.
    - For `:FullLU`, we use the default linear solver on a sparse matrix representation of `dG`. This matrix is assembled at each newton iteration.
    - For `:FullSparseInplace`, this is the same as for `:FullLU` but the sparse matrix `dG` is updated inplace. This method allocates much less. In some cases, this is significantly faster than using `:FullLU`. Note that this method can only be used if the sparsity pattern of the jacobian is always the same.
    - For `:BorderedLU`, we take advantage of the bordered shape of the linear solver and use LU decomposition to invert `dG` using a bordered linear solver. This is the default algorithm.
    - For `:FullMatrixFree`, a matrix free linear solver is used for `dG`: note that a preconditioner is very likely required here because of the cyclic shape of `dG` which affects negatively the convergence properties of GMRES.
    - For `:BorderedMatrixFree`, a matrix free linear solver is used but for `Jc` only (see docs): it means that `options.linsolver` is used to invert `Jc`. These two Matrix-Free options thus expose different part of the jacobian `dG` in order to use specific preconditioners. For example, an ILU preconditioner on `Jc` could remove the constraints in `dG` and lead to poor convergence. Of course, for these last two methods, a preconditioner is likely to be required.

# Output:
- solution
- history of residuals
- flag of convergence
- number of iterations
"""
newton(probPO::PeriodicOrbitTrapProblem, orbitguess, options::NewtonPar, linearPO::Symbol = :BorderedLU; kwargs...) = _newton(probPO, orbitguess, options, linearPO; defOp = nothing, kwargs...)

"""
	newton(probPO::PeriodicOrbitTrapProblem, orbitguess, options::NewtonPar, defOp::DeflationOperator{T, Tf, vectype}, linearPO = :BorderedLU; kwargs...) where {T, Tf, vectype}

This function is similar to `newton(probPO, orbitguess, options, linearPO; kwargs...)` except that it uses deflation in order to find periodic orbits different from the one in `defOp`. We refer to the mentioned method for a full description of the arguments. The current method can be used in the vicinity of a Hopf bifurcation to prevent the Newton algorithm from converging to the equilibrium point. We refer
"""
newton(probPO::PeriodicOrbitTrapProblem, orbitguess, options::NewtonPar, defOp::DeflationOperator{T, Tf, vectype}, linearPO::Symbol; kwargs...) where {T, Tf, vectype} = _newton(probPO, orbitguess, options, linearPO; defOp = defOp, kwargs...)

####################################################################################################
# continuation wrapper

"""
	continuationPOTrap(probPO, orbitguess, p0::Real, _contParams::ContinuationPar, linearAlgo::AbstractBorderedLinearSolver; linearPO = :BorderedLU, printSolution = (u,p) -> u[end], kwargs...)

This is the continuation routine for computing a periodic orbit using a functional G based on Finite Differences and a Trapezoidal rule.

# Arguments
- `p -> prob(p)` is a family such that `prob(p)::PeriodicOrbitTrapProblem` encodes the functional G
- `orbitguess` a guess for the periodic orbit where `orbitguess[end]` is an estimate of the period of the orbit. It could be a vector of size `N * M + 1` where `M` is the number of time slices, `N` is the dimension of the phase space. This must be compatible with the numbers `N, M` in `prob`.
- `p0` initial parameter, must be a real number
- `contParams` same as for the regular `continuation` method
- `linearAlgo` same as in [`continuation`](@ref)
- `linearPO = :BorderedLU`. Same as `newton` when applied to `PeriodicOrbitTrapProblem`. More precisely:
    - For `:FullLU`, we use the default linear solver on a sparse matrix representation of `dG`. This matrix is assembled at each newton iteration.
    - For `:FullSparseInplace`, this is the same as for `:FullLU` but the sparse matrix `dG` is updated inplace. This method allocates much less. In some cases, this is significantly faster than using `:FullLU`. Note that this method can only be used if the sparsity pattern of the jacobian is always the same.
    - For `:BorderedLU`, we take advantage of the bordered shape of the linear solver and use LU decomposition to invert `dG` using a bordered linear solver. This is the default algorithm.
    - For `:FullMatrixFree`, a matrix free linear solver is used for `dG`: note that a preconditioner is very likely required here because of the cyclic shape of `dG` which affects negatively the convergence properties of GMRES.
    - For `:BorderedMatrixFree`, a matrix free linear solver is used but for `Jc` only (see docs): it means that `options.linsolver` is used to invert `Jc`. These two Matrix-Free options thus expose different part of the jacobian `dG` in order to use specific preconditioners. For example, an ILU preconditioner on `Jc` could remove the constraints in `dG` and lead to poor convergence. Of course, for these last two methods, a preconditioner is likely to be required.


Note that by default, the methods prints the period of the periodic orbit as function of the parameter. This can be changed by providing your `printSolution` argument.
"""
function continuationPOTrap(probPO, orbitguess, p0::Real, _contParams::ContinuationPar, linearAlgo::AbstractBorderedLinearSolver; linearPO = :BorderedLU, printSolution = (u,p) -> u[end], kwargs...)
	@assert linearPO in [:FullLU, :FullMatrixFree, :BorderedLU, :BorderedMatrixFree, :FullSparseInplace]
	contParams = check(_contParams)

	_pb = probPO(p0)
	N = _pb.N
	M = _pb.M
	options = contParams.newtonOptions

	if contParams.computeEigenValues
		contParams = @set contParams.newtonOptions.eigsolver = FloquetQaDTrap(contParams.newtonOptions.eigsolver)
	end

	if linearPO in [:FullLU, :FullMatrixFree, :FullSparseInplace]
		@assert length(orbitguess) == N * M + 1 "Error with size of the orbitguess"

		if linearPO == :FullLU
			jac = (x, p) -> probPO(p)(Val(:JacFullSparse), x)
		elseif linearPO == :FullSparseInplace
			# sparse matrix to hold the jacobian
			_J =  _pb(Val(:JacFullSparse), orbitguess)
			_indx = getBlocks(_J, N, M)
			# inplace modification of the jacobian _J
			jac = (x, p) -> probPO(p)(Val(:JacFullSparseInplace), _J, x, _indx)
		else
		 	jac = (x, p) ->  ( dx -> probPO(p)(x, dx))
		end

		lspo = PeriodicOrbitTrapLS(options.linsolver)

		return continuation(
			(x, p) -> probPO(p)(x),
			(x, p) -> PeriodicOrbitTrapJacobianFull(probPO(p), jac(x, p), x),
			orbitguess, p0,
			(@set contParams.newtonOptions.linsolver = lspo);
			printSolution = printSolution,
			kwargs...)
	else
		@assert orbitguess isa AbstractVector
		@assert length(orbitguess) == N * M + 1 "Error with size of the orbitguess"

		if linearPO == :BorderedLU
			Aγ = AγOperator(is_matrix_free = false,
					N = probPO(p0).N,
					Jc = lu(spdiagm( 0 => ones(N * (M - 1)) )) )
			# linear solver
			lspo = PeriodicOrbitTrapBLS()
		else
			Aγ = AγOperator(is_matrix_free = true, prob = probPO(p0),
					N = probPO(p0).N,
					orbitguess = zeros(N * M + 1),
					Jc = lu(spdiagm( 0 => ones(N * (M - 1)) )) )
			# linear solver
			lspo = PeriodicOrbitTrapBLS(BorderingBLS(AγLinearSolver(options.linsolver)))
		end

		# create the jacobian
		JacPO = p -> PeriodicOrbitTrapJacobianBordered(probPO(p), zeros(N * M + 1), Aγ, zeros(N * M + 1))

		return continuation(
			(x, p) -> probPO(p)(x),
			(x, p) ->  JacPO(p)(x),
			orbitguess, p0,
			(@set contParams.newtonOptions.linsolver = lspo);
			printSolution = printSolution,
			kwargs...)
	end
end

"""
	continuationPOTrap(probPO, orbitguess, p0::Real, _contParams::ContinuationPar; linearPO = :BorderedLU, printSolution = (u,p) -> u[end], linearAlgo = BorderingBLS(), kwargs...)

This is the continuation routine for computing a periodic orbit using a functional G based on Finite Differences and a Trapezoidal rule.

# Arguments
- `p -> prob(p)` is a family such that `prob(p)::PeriodicOrbitTrapProblem` encodes the functional G
- `orbitguess` a guess for the periodic orbit where `orbitguess[end]` is an estimate of the period of the orbit. It could be a vector of size `N * M + 1` where `M` is the number of time slices, `N` is the dimension of the phase space. This must be compatible with the numbers `N, M` in `prob`.
- `p0` initial parameter, must be a real number
- `contParams` same as for the regular `continuation` method
- `linearPO = :BorderedLU`. Same as `newton` when applied to `PeriodicOrbitTrapProblem`.

Note that by default, the methods prints the period of the periodic orbit as function of the parameter. This can be changed by providing your `printSolution` argument.
"""
function continuationPOTrap(probPO, orbitguess, p0::Real, _contParams::ContinuationPar; linearPO = :BorderedLU, printSolution = (u,p) -> u[end], linearAlgo = BorderingBLS(), kwargs...)
	_linearAlgo = @set linearAlgo.solver = _contParams.newtonOptions.linsolver
	return continuationPOTrap(probPO, orbitguess, p0, _contParams, _linearAlgo; linearPO = linearPO, printSolution = printSolution, kwargs...)
end
