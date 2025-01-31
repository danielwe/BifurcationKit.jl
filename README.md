# BifurcationKit.jl

| **Documentation** | **Build Status** | **Downloads** |
|:-----------------:|:----------------:|:-------------:|
| [![docs-stable][docs-stable-img]][docs-stable-url] [![docs-dev][docs-dev-img]][docs-dev-url] | [![Build status](https://badge.buildkite.com/fc3fdd514333077cbb6600923ed0ef631a59de5226b197665f.svg)](https://buildkite.com/julialang/bifurcationkit-dot-jl) [![Build status](https://github.com/rveltz/BifurcationKit.jl/workflows/CI/badge.svg)](https://github.com/rveltz/BifurcationKit.jl/actions) [![codecov](https://codecov.io/gh/bifurcationkit/BifurcationKit.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/bifurcationkit/BifurcationKit.jl) | [![](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/BifurcationKit)](https://pkgs.genieframework.com?packages=BifurcationKit)|

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://bifurcationkit.github.io/BifurcationKitDocs.jl/stable
[docs-dev-img]: https://img.shields.io/badge/docs-dev-purple.svg
[docs-dev-url]: https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev

This Julia package aims at performing **automatic bifurcation analysis** of possibly large dimensional equations F(u, λ)=0 where λ∈ℝ by taking advantage of iterative methods, dense / sparse formulation and specific hardwares (*e.g.* GPU).

It incorporates continuation algorithms (PALC, deflated continuation, ...) based on a Newton-Krylov method to correct the predictor step and a Matrix-Free/Dense/Sparse eigensolver is used to compute stability and bifurcation points.

> The idea is to be able to seemingly switch the continuation algorithm a bit like changing the time stepper (Euler, RK4,...) for ODEs.

`BifurcationKit` can also seek for periodic orbits of Cauchy problems. **It is by now, one of the only softwares which provides shooting methods AND methods based on finite differences or collocation to compute periodic orbits.**

The current focus is on large scale nonlinear problems and multiple hardwares. Hence, the goal is to use Matrix Free methods on **GPU** (see [PDE example](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials2b/#The-Swift-Hohenberg-equation-on-the-GPU-(non-local)-1) and [Periodic orbit example](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsCGL/#Continuation-of-periodic-orbits-on-the-GPU-(Advanced)-1)) or on a **cluster** to solve non linear PDE, nonlocal problems, compute sub-manifolds...

> Despite this focus, the package can easily handle low dimensional problems and specific optimizations are regularly added.


## Support and citation
If you use `BifurcationKit.jl` in your work, we ask that you cite the following paper. Open source development as part of academic research strongly depends on this. Please also consider starring this repository if you like our work, this will help us to secure funding in the future. It is referenced on HAL-Inria as follows:

```
@misc{veltz:hal-02902346,
  TITLE = {{BifurcationKit.jl}},
  AUTHOR = {Veltz, Romain},
  URL = {https://hal.archives-ouvertes.fr/hal-02902346},
  INSTITUTION = {{Inria Sophia-Antipolis}},
  YEAR = {2020},
  MONTH = Jul,
  KEYWORDS = {pseudo-arclength-continuation ; periodic-orbits ; floquet ; gpu ; bifurcation-diagram ; deflation ; newton-krylov},
  PDF = {https://hal.archives-ouvertes.fr/hal-02902346/file/354c9fb0d148262405609eed2cb7927818706f1f.tar.gz},
  HAL_ID = {hal-02902346},
  HAL_VERSION = {v1},
}
```

## Installation

This package requires Julia >= v1.3.0

To install it, please run

`] add BifurcationKit`

To install the bleeding edge version, please run

`] add BifurcationKit#master`

## Plugins

Most plugins are located in the organization [bifurcationkit](https://github.com/bifurcationkit):

- [HclinicBifurcationKit.jl](https://github.com/bifurcationkit/HclinicBifurcationKit.jl) computation and bifurcation analysis of homoclinic / heteroclinic orbits of ordinary differential equations (ODE)
- [DDEBifurcationKit.jl](https://github.com/bifurcationkit/DDEBifurcationKit.jl) bifurcation analysis of delay differential equations (DDE)
- [AsymptoticNumericalMethod.jl](https://github.com/bifurcationkit/AsymptoticNumericalMethod.jl) provides the numerical continuation algorithm **Asymptotic Numerical Method** (ANM) which can be used directly in `BifurcationKit.jl`
- [GridapBifurcationKit.jl](https://github.com/bifurcationkit/GridapBifurcationKit) bifurcation analysis of PDEs solved with the Finite Elements Method (FEM) using the package [Gridap.jl](https://github.com/gridap/Gridap.jl).
- [PeriodicSchurBifurcationKit.jl](https://github.com/bifurcationkit/PeriodicSchurBifurcationKit.jl) state of the art computation of Floquet coefficients, useful for computing the stability of periodic orbits.

## Overview of capabilities

The list of capabilities is available [here](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/capabilities/).

## Examples of bifurcation diagrams (ODEs and PDEs)

| ![](https://github.com/bifurcationkit/BifurcationKitDocs.jl/blob/main/docs/src/tutorials/ode/nm-per.png?raw=true)   |  ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/ode/com-fig3.png?raw=true) |
|:-------------:|:-------------:|
| [simple ODE example](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/ode/tutorialsODE/#Neural-mass-equation-(Hopf-aBS)) |  [Codimension 2 (ODE)](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/ode/tutorialCO/#CO-oxydation-(codim-2)) |
| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/BDSH1d.png)   |  ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/mittlemannBD-1.png) |
| [Automatic Bif. Diagram in 1D Swift Hohenberg](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/Swift-Hohenberg1d/#d-Swift-Hohenberg-equation-(Automatic)) |  [Automatic Bif. Diagram in 2D Bratu](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/mittelmannAuto/#Automatic-diagram-of-2d-Bratu–Gelfand-problem-(Intermediate)) |
| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/sh2dbranches.png)   |  ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/bru-po-cont-3br.png) |
| [Snaking in 2D Swift Hohenberg](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials2/#d-Swift-Hohenberg-equation:-snaking,-Finite-Differences) |  [Periodic orbits in 1D Brusselator](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials3/#d-Brusselator-(automatic))
| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/br_pd3.png) |![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/cgl-sh-br.png) |
| [Period doubling BVAM Model](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsPD/#Period-doubling-in-the-Barrio-Varea-Aragon-Maini-model)  |  [Periodic orbits in 2D Ginzburg-Landau](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsCGL/#d-Ginzburg-Landau-equation-(finite-differences))  |
| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/carrier.png) | ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/GPU-branch.png) |
| [Deflated Continuation in Carrier problem](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialCarrier/#Deflated-Continuation-in-the-Carrier-Problem)  |  [2D Swift Hohenberg on GPU](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials2b/#d-Swift-Hohenberg-equation-(non-local)-on-the-GPU,-periodic-BC-(Advanced))  |

