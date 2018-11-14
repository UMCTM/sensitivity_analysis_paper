# =============================================================== #
# Small regime (2x3 Jacobian matrix)

include("sensitivity.jl")
using DiffEqSensitivity, OrdinaryDiffEq, ForwardDiff, BenchmarkTools, StaticArrays#, Profile, ProfileView

include("lotka-volterra.jl")

u0 = [1.,1.]; tspan = (0., 10.); p = [1.5,1.0,3.0]
lvcom_u0 = [u0...;zeros(6)]
comprob = ODEProblem(lvcom_df, lvcom_u0, tspan, p)
#=
f = function (u, p, t)
    a,b,c = p
    x, y = u
    dx = a*x - b*x*y
    dy = -c*y + x*y
    @SVector [dx, dy]
end

# Using `SVector` doesn't give any significant run-time benefits, but increases
# compile time drastically

u0s = @SVector [1.,1.]; sp = @SVector [1.5,1.0,3.0];
@time auto_sen(f, u0s, tspan, sp, Vern9(), abstol=1e-5,reltol=1e-7)
# 139.719343 seconds (22.66 M allocations: 1.558 GiB, 0.58% gc time)
@btime auto_sen($f, $u0s, $tspan, $sp, $(Vern9()), abstol=1e-5,reltol=1e-7)
# 135.706 μs (499 allocations: 84.55 KiB)
=#

@time numerical_sen(lvdf, u0, tspan, p, Vern9(), abstol=1e-5,reltol=1e-7)
# 3.401622 seconds (7.42 M allocations: 387.500 MiB, 6.50% gc time)
@time auto_sen(lvdf, u0, tspan, p, Vern9(), abstol=1e-5,reltol=1e-7)
# 13.564837 seconds (43.31 M allocations: 2.326 GiB, 9.15% gc time)
@time diffeq_sen(lvdf, u0, tspan, p, Vern9(), abstol=1e-5,reltol=1e-7)
# 5.712511 seconds (16.38 M allocations: 931.242 MiB, 9.13% gc time)
# with seeding 10.179159 seconds (32.43 M allocations: 1.730 GiB, 9.75% gc time)
@time diffeq_sen(lvdf_with_jacobian, u0, tspan, p, Vern9(), abstol=1e-5,reltol=1e-7)
# 2.679172 seconds (6.21 M allocations: 320.881 MiB, 5.36% gc time)
@time solve(comprob, Vern9(),abstol=1e-5,reltol=1e-7,save_everystep=false)
# 3.484515 seconds (8.10 M allocations: 417.261 MiB, 7.50% gc time)

@btime numerical_sen($lvdf, $u0, $tspan, $p, $(Vern9()), abstol=1e-5,reltol=1e-7)
# 534.718 μs (2614 allocations: 222.88 KiB)
@btime auto_sen($lvdf, $u0, $tspan, $p, $(Vern9()), abstol=1e-5,reltol=1e-7)
# 99.404 μs (485 allocations: 57.11 KiB)
@btime diffeq_sen($lvdf, $u0, $tspan, $p, $(Vern9()), abstol=1e-5,reltol=1e-7)
# 308.289 μs (8137 allocations: 391.78 KiB)
# with seeding 268.012 μs (8310 allocations: 406.86 KiB)
@btime diffeq_sen($lvdf_with_jacobian, $u0, $tspan, $p, $(Vern9()), abstol=1e-5,reltol=1e-7)
# 263.562 μs (8084 allocations: 389.08 KiB)
@btime solve($comprob, $(Vern9()),abstol=1e-5,reltol=1e-7,save_everystep=false)
# 36.517 μs (111 allocations: 14.67 KiB)

@btime numerical_sen($lvdf, $u0, $tspan, $p, $(Vern9()))
# 472.643 μs (2585 allocations: 222.13 KiB)
@btime auto_sen($lvdf, $u0, $tspan, $p, $(Vern9()))
# 90.698 μs (467 allocations: 56.95 KiB)
@btime diffeq_sen($lvdf, $u0, $tspan, $p, $(Vern9()))
# 255.729 μs (5849 allocations: 292.16 KiB)
@btime diffeq_sen($lvdf_with_jacobian, $u0, $tspan, $p, $(Vern9()))
# 192.806 μs (5619 allocations: 273.50 KiB)
@btime solve($comprob, $(Vern9()),save_everystep=false)
# 27.937 μs (112 allocations: 14.66 KiB)

# =============================================================== #
# Large regime (128x3 Jacobian matrix)
using LinearAlgebra, Test
include("brusselator.jl")
DiffEqBase.has_tgrad(::ODELocalSensitvityFunction) = false
DiffEqBase.has_invW(::ODELocalSensitvityFunction) = false
DiffEqBase.has_jac(::ODELocalSensitvityFunction) = false

bfun, b_u0, brusselator_jac,brusselator_comp = makebrusselator(5)
# Run low tolerance to test correctness
sol1 = @time numerical_sen(bfun, b_u0, (0.,10.), [3.4, 1., 10.], Rodas5(), abstol=1e-5,reltol=1e-7);
#  4.086760 seconds (11.94 M allocations: 615.768 MiB, 8.97% gc time)
sol2 = @time auto_sen(bfun, b_u0, (0.,10.), [3.4, 1., 10.], Rodas5(), abstol=1e-5,reltol=1e-7);
#  6.404542 seconds (18.41 M allocations: 862.547 MiB, 9.09% gc time)
sol3 = @time diffeq_sen(bfun, b_u0, (0.,10.), [3.4, 1., 10.], Rodas5(autodiff=false), abstol=1e-5,reltol=1e-7);
#  3.390236 seconds (5.19 M allocations: 253.180 MiB, 4.74% gc time)
sol4 = @time diffeq_sen(ODEFunction(bfun, jac=brusselator_jac), b_u0, (0.,10.), [3.4, 1., 10.], Rodas5(autodiff=false), abstol=1e-5,reltol=1e-7);
#  3.018417 seconds (6.22 M allocations: 339.178 MiB, 4.57% gc time)
sol5 = @time solve(brusselator_comp, Rodas5(), abstol=1e-5,reltol=1e-7,save_everystep=false);
#  2.699624 seconds (6.05 M allocations: 347.092 MiB, 4.42% gc time)

@btime numerical_sen($bfun, $b_u0, $((0.,10.)), $([3.4, 1., 10.]), $(Rodas5()), abstol=1e-5,reltol=1e-7);
# 138.664 ms (5805 allocations: 959.64 KiB)
@btime auto_sen($bfun, $b_u0, $((0.,10.)), $([3.4, 1., 10.]), $(Rodas5()), abstol=1e-5,reltol=1e-7);
# 33.484 ms (3695 allocations: 409.98 KiB)
@btime diffeq_sen($bfun, $b_u0, $((0.,10.)), $([3.4, 1., 10.]), $(Rodas5(autodiff=false)), abstol=1e-5,reltol=1e-7);
# 742.538 ms (755818 allocations: 35.55 MiB)
# without seeding 2.076 s (755821 allocations: 35.58 MiB)
@btime diffeq_sen($(ODEFunction(bfun, jac=brusselator_jac)), $b_u0, $((0.,10.)), $([3.4, 1., 10.]), $(Rodas5(autodiff=false)), abstol=1e-5,reltol=1e-7);
# 899.607 ms (1991090 allocations: 131.91 MiB)
@btime solve($brusselator_comp, $(Rodas5(autodiff=false)), abstol=1e-5,reltol=1e-7,save_everystep=false);
# 913.413 ms (1991060 allocations: 147.59 MiB)

difference1 = copy(sol2)
difference2 = copy(sol2)
difference3 = vec(sol2) .- vec(sol5[2][5*5*2+1:end])
for i in eachindex(sol3)
    difference1[:, i] .-= sol3[i]
    difference2[:, i] .-= sol4[i]
end
@test norm(difference1) < 0.01 && norm(difference2) < 0.01 && norm(difference3) < 0.01 && norm(sol5[end][51:end] .- vec(sol1)) < 0.01

# # High tolerance to benchmark
bfun_n, b_u0_n, brusselator_jacn, b_comp = makebrusselator(8)
@time numerical_sen(bfun_n, b_u0_n, (0.,10.), [3.4, 1., 10.])
# 57.474043 seconds (1.32 G allocations: 25.101 GiB, 9.46% gc time)
@time auto_sen(bfun_n, b_u0_n, (0.,10.), [3.4, 1., 10.])
#  13.632362 seconds (238.33 M allocations: 10.063 GiB, 15.94% gc time)
@time diffeq_sen(bfun_n, b_u0_n, (0.,10.), [3.4, 1., 10.])
# 302.428220 seconds (3.42 G allocations: 216.285 GiB, 12.05% gc time)
# with seeding 42.514960 seconds (1.10 G allocations: 29.561 GiB, 14.89% gc time)
@time diffeq_sen(ODEFunction(bfun_n, jac=brusselator_jacn), b_u0_n, (0.,10.), [3.4, 1., 10.])
#  36.712953 seconds (442.08 M allocations: 10.215 GiB, 6.01% gc time)
@time solve(b_comp, Tsit5(), abstol=1e-5,reltol=1e-7,save_everystep=false)
#  12.807239 seconds (249.44 M allocations: 4.843 GiB, 10.15% gc time)

# 20×25 Jacobian
include("pollution.jl")
pcomp, pu0, pp, pcompu0 = make_pollution(pollution)
using BenchmarkTools
DiffEqBase.has_tgrad(::ODELocalSensitvityFunction) = false
DiffEqBase.has_invW(::ODELocalSensitvityFunction) = false
DiffEqBase.has_jac(::ODELocalSensitvityFunction) = false

ptspan = (0.,60.)
@btime auto_sen($(ODEFunction(pollution.f)), $pu0, $ptspan, $pp, $(Rodas5()),abstol=1e-5,reltol=1e-7)
# 8.075 ms (3051 allocations: 607.67 KiB)
@btime diffeq_sen($(ODEFunction(pollution.f)), $pu0, $ptspan, $pp, $(Rodas5(autodiff=false)),abstol=1e-5,reltol=1e-7,sensalg=SensitivityAlg(autojacvec=false))
# 945.459 ms (3723192 allocations: 174.89 MiB)
@btime diffeq_sen($(ODEFunction(pollution.f)), $pu0, $ptspan, $pp, $(Rodas5(autodiff=false)),abstol=1e-5,reltol=1e-7)
# with seeding 762.009 ms (3723189 allocations: 174.88 MiB)
@btime diffeq_sen($(ODEFunction(pollution.f, jac=pollution.jac)), $pu0, $ptspan, $pp, $(Rodas5(autodiff=false)),abstol=1e-5,reltol=1e-7) # with Jacobian
# 994.041 ms (3723186 allocations: 174.89 MiB)
@btime solve($(ODEProblem(pcomp, pcompu0, ptspan, (pp, pollution, zeros(20, 20), zeros(20, 25), zeros(20,25), zeros(20,25)))), $(Rodas5(autodiff=false)),abstol=1e-5,reltol=1e-7,save_everystep=false)
# 522.323 ms (292060 allocations: 12.62 MiB)

include("pkpd.jl")
@btime auto_sen($pkpdprob, $(Vern9()),abstol=1e-5,reltol=1e-7,callback=pkpdcb,tstops=1:2:49)
# 4.349 ms (10148 allocations: 568.95 KiB)
#  [-1.25782 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 0.0011805 -0.0124523 -0.049443 0.0392673 0.052271 -0.000116164 -0.000116164 -0.000159553 -0.000159553 0.0 0.0 0.0 0.0 0.0; 0.00127647 -0.0121023 -0.0482426 0.0384692 -0.000292376 0.000926783 -0.00017142 0.0501059 2.62154e-6 0.0 0.0 0.0 0.0 0.0; 0.00127647 -0.0121023 -0.0482426 0.0384692 -0.000292376 -0.00017142 0.000926783 2.62154e-6 0.0501059 0.0 0.0 0.0 0.0 0.0; -0.000163114 0.0116831 0.0466874 -0.0373218 2.75921e-5 1.19409e-5 1.19409e-5 -3.21866e-6 -3.21866e-6 4.56854 -4.56697 0.0490499 -0.43123 0.0678703]


@btime diffeq_sen($pkpdprob, $(Vern9()), abstol=1e-5,reltol=1e-7,callback=pkpdcb,tstops=1:2:49)
# 17.474 ms (134146 allocations: 6.21 MiB)
# [-1.25782, 0.0011805, 0.00127647, 0.00127647, -0.000163114]
# [0.0, -0.0124523, -0.0121023, -0.0121023, 0.0116831]
# [0.0, -0.049443, -0.0482426, -0.0482426, 0.0466874]
# [0.0, 0.0392673, 0.0384692, 0.0384692, -0.0373218]
# [0.0, 0.052271, -0.000292375, -0.000292375, 2.75942e-5]
# [0.0, -0.000116164, 0.000926783, -0.00017142, 1.19403e-5]
# [0.0, -0.000116164, -0.00017142, 0.000926783, 1.19403e-5]
# [0.0, -0.000159553, 0.0501059, 2.62159e-6, -3.21856e-6]
# [0.0, -0.000159553, 2.62159e-6, 0.0501059, -3.21856e-6]
# [0.0, 0.0, 0.0, 0.0, 4.56854]
# [0.0, 0.0, 0.0, 0.0, -4.56697]
# [0.0, 0.0, 0.0, 0.0, 0.0490499]
# [0.0, 0.0, 0.0, 0.0, -0.43123]
# [0.0, 0.0, 0.0, 0.0, 0.0678703]

using Test
diffeqpkpd = diffeq_sen(pkpdprob, Vern9(), abstol=1e-5,reltol=1e-7,callback=pkpdcb,tstops=1:2:49)
autopkpd = auto_sen(pkpdprob, Vern9(), abstol=1e-5,reltol=1e-7,callback=pkpdcb,tstops=1:2:49)
@test hcat(diffeqpkpd...) ≈ autopkpd atol=1e-5
