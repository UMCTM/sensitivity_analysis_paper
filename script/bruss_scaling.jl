include("sensitivity.jl")
include("brusselator.jl")

using DiffEqSensitivity, OrdinaryDiffEq, ForwardDiff, ReverseDiff, DiffEqDiffTools
using DiffEqSensitivity: alg_autodiff
using LinearAlgebra
using Test

bt = 0:0.1:1
tspan = (0.0, 1.0)
forwarddiffn = vcat(2:10,12,15)
reversediffn = 2:10
numdiffn = vcat(2:10,12)
csan = vcat(2:10,12,15,17)
#csaseedn = 2:10
tols = (abstol=1e-5, reltol=1e-7)

@isdefined(PROBS) || (const PROBS = Dict{Int,Any}())
makebrusselator!(dict, n) = get!(()->makebrusselator(n), dict, n)

println("Forward Diff")
forwarddiff = map(forwarddiffn) do n
  bfun, b_u0, b_p, brusselator_jac, brusselator_comp = makebrusselator!(PROBS, n)
  @elapsed auto_sen_l2(bfun, b_u0, tspan, b_p, bt, (Rodas5()); diffalg=(ForwardDiff.gradient), tols...)
  t = @elapsed auto_sen_l2(bfun, b_u0, tspan, b_p, bt, (Rodas5()); diffalg=(ForwardDiff.gradient), tols...)
  @show n,t
  t
end

println("Reverse Diff")
reversediff = map(reversediffn) do n
  bfun, b_u0, b_p, brusselator_jac, brusselator_comp = makebrusselator!(PROBS, n)
  @elapsed auto_sen_l2(bfun, b_u0, tspan, b_p, bt, (Rodas5(autodiff=false)); diffalg=(ReverseDiff.gradient), tols...)
  t = @elapsed auto_sen_l2(bfun, b_u0, tspan, b_p, bt, (Rodas5(autodiff=false)); diffalg=(ReverseDiff.gradient), tols...)
  @show n,t
  t
end

println("Num Diff")
numdiff = map(numdiffn) do n
  bfun, b_u0, b_p, brusselator_jac, brusselator_comp = makebrusselator!(PROBS, n)
  @elapsed auto_sen_l2(bfun, b_u0, tspan, b_p, bt, (Rodas5()); diffalg=(DiffEqDiffTools.finite_difference_gradient), tols...)
  t = @elapsed auto_sen_l2(bfun, b_u0, tspan, b_p, bt, (Rodas5()); diffalg=(DiffEqDiffTools.finite_difference_gradient), tols...)
  @show n,t
  t
end

println("CSA")
csa = map(csan) do n
  bfun, b_u0, b_p, brusselator_jac, brusselator_comp = makebrusselator!(PROBS, n)
  @time ts = map(ADJOINT_METHODS[1:2end÷3]) do alg
    @info "Runing $alg"
    f = alg_autodiff(alg) ? bfun : ODEFunction(bfun, jac=brusselator_jac)
    solver = Rodas5(autodiff=false)
    @time diffeq_sen_l2(bfun, b_u0, tspan, b_p, bt, solver; sensalg=alg, tols...)
    t = @elapsed diffeq_sen_l2(bfun, b_u0, tspan, b_p, bt, solver; sensalg=alg, tols...)
    return t
  end
  @show n,ts
  ts
end

open("../bruss_scaling_data.txt", "w+") do f
  write(f, "forwarddiffn = $forwarddiffn \n")
  write(f, "forwarddiff = $forwarddiff \n")
  write(f, "reversediffn = $reversediffn \n")
  write(f, "reversediff = $reversediff \n")
  write(f, "numdiffn = $numdiffn \n")
  write(f, "numdiff = $numdiff \n")
  write(f, "csan = $csan \n")
  write(f, "csa = $csa \n")
end
