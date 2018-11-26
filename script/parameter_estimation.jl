using Optim, BenchmarkTools, Random
using Test
include("sensitivity.jl")

function param_benchmark(fun, compfun, jac, u0, compu0, tspan, p, t, p0;
                           alg=Tsit5(), lower=0.4.*p, upper=1.6.*p, save_everystep=false,
                           verbose=false, iter=2, dropfirst=true, kwargs...)
  prob_original = ODEProblem(fun, u0, tspan, p)
  data = solve(prob_original, alg; saveat=t, save_everystep=save_everystep, kwargs...)
  t = collect(t)
  function l2loss(sol, data)
    l2loss_ = zero(eltype(data))
    for j in 1:size(data, 2), i in 1:size(data, 1)
      l2loss_ += (sol[i,j] - data[i,j])^2
    end
    l2loss_
  end
  function costfunc(p,data,df,t,u0)
    tmp_prob = ODEProblem(df, u0, tspan, p)
    sol = solve(tmp_prob, alg; saveat=t, save_everystep=save_everystep, kwargs...)
    loss = l2loss(sol,data)
    verbose && @info "L2 Loss: $loss"
    return loss
  end
  function l2lossgradient!(grad,sol,data,sensitivities,num_p)
    fill!(grad,0.0)
    data_x_size = size(data,1)
    my_grad = @. -2 * (data - sol)
    u0len = length(data[1])
    K = size(my_grad,2)
    for k in 1:K, i in 1:num_p, j in 1:data_x_size
      grad[i] += my_grad[j,k]*sensitivities[i][j,k]
    end
  end
  # forward
  function costfunc_gradient_diffeq(grad,p,df,u0,tspan,data,t;kwargs...)
    sol,sensitivities = diffeq_sen_full(df,u0,tspan,p,t; kwargs...)
    l2lossgradient!(grad,sol,data,sensitivities,length(p))
  end
  function costfunc_gradient_autosen(grad,p,df,u0,tspan,data,t;kwargs...)
    sol, sensitivities = auto_sen_full(df, u0, tspan, p, t; kwargs...)
    l2lossgradient!(grad,sol,data,sensitivities,length(p))
  end
  function costfunc_gradient_num(grad,p,df,u0,tspan,data,t;kwargs...)
    sol, sensitivities = numerical_sen_full(df, u0, tspan, p, t; kwargs...)
    l2lossgradient!(grad,sol,data,sensitivities,length(p))
  end
  function costfunc_gradient_comp(grad,p,comdf,u0,tspan,data,t; kwargs...)
    comprob = ODEProblem(comdf, u0, tspan, p)
    sol = reshape(vec(solve(comprob, alg; saveat=t, save_everystep=save_everystep, kwargs...)), length(u0), length(t))
    nvar = length(data[1])
    l2lossgradient!(grad,sol[1:nvar,:],data,[sol[i*nvar+1:i*nvar+nvar,:] for i in 1:length(p)], length(p))
  end
  # adjoint
  function adjoint_diffeq_grad(grad, p, df, u0, tspan, data, t; alg, sensalg, kwargs...)
    tspan = (tspan[1]-0.01, tspan[2]+0.01)
    prob = ODEProblem(df, u0, tspan, p)
    saveat = tspan[1] != t[1] && tspan[end] != t[end] ? vcat(tspan[1],t,tspan[end]) : t # so that finite diff works
    sol = solve(prob, alg; saveat=saveat, save_start=true, save_end=true, kwargs...)
    dg = let data=data
      function (out, u, p, t, i)
        @. out = 2*(data.u[i] - u)
        nothing
      end
    end
    _grad = adjoint_sensitivities(sol, alg, dg, t; sensealg=sensalg, kwargs...)
    copyto!(grad, _grad)
    nothing
  end
  function adjoint_diff_grad(grad, p, df, u0, tspan, data, t; alg, diffalg, kwargs...)
    test_f(p) = begin
      prob = ODEProblem(df,eltype(p).(u0),tspan,p)
      sol = solve(prob,alg,saveat=t; kwargs...)
      sum(x->norm(x)^2, Broadcast.broadcasted(-, data.u, sol.u))
    end
    _grad = diffalg(test_f, p)
    copyto!(grad, _grad)
    nothing
  end
  inner_optimizer = BFGS()
  opt = Optim.Options(x_tol=1e-4, f_tol=1e-4, g_tol=3e-3)
  cost = let p=p, data=data, fun=fun, t=t, u0=u0
    p->costfunc(p,data,fun,t,u0)
  end
  forward_timings, adjoint_timings = let p=p, data=data, fun=fun, t=t, u0=u0, tspan=tspan, compu0=compu0, compfun=compfun, fun=fun
    t1, t2, t3, t4, t5, t6 = zeros(6)
    a1, a2, a3, a4, a5, a6 = zeros(6)
    for i in 1:iter
      @info " Iteration $i"
      @info " Forward SA"
      @info "  Running compile-time"
      t1 += @elapsed (s=optimize(
        cost,
        (grad,p)->costfunc_gradient_comp(
           grad,p,compfun,compu0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  Running DSA"
      t2 += @elapsed (s=optimize(
        cost,
        (grad,p)->costfunc_gradient_autosen(
          grad,p,fun,u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  Running CSA with user-Jacobian"
      t3 += @elapsed (s=optimize(
        cost,
        (grad,p)->costfunc_gradient_diffeq(
          grad,p,ODEFunction(fun, jac=jac),u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  Running CSA AD-Jacobian"
      t4 += @elapsed (s=optimize(
        cost,
        (grad,p)->costfunc_gradient_diffeq(
          grad,p,fun,u0,tspan,data,t; sensalg=SensitivityAlg(autojacvec=false),
          saveat=t, alg=alg, save_everystep=save_everystep,kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  Running CSA AD-Jv seeding"
      t5 += @elapsed (s=optimize(
        cost,
        (grad,p)->costfunc_gradient_diffeq(
          grad,p,fun,u0,tspan,data,t; sensalg=SensitivityAlg(autojacvec=true),
          saveat=t, alg=alg, save_everystep=save_everystep,kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  Running numerical differentiation"
      t6 += @elapsed (s=optimize(
        cost,
        (grad,p)->costfunc_gradient_num(
          grad,p,fun,u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s))
      @info " Adjoint SA"
      @info "  Forward-Mode DSAAD"
      a1 += @elapsed (s=optimize(
        cost,
        (grad,p)->adjoint_diff_grad(
          grad,p,fun,u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,
          diffalg=ForwardDiff.gradient, kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  Reverse-Mode DSAAD"
      a2 += @elapsed (s=optimize(
        cost,
        (grad,p)->adjoint_diff_grad(
          grad,p,fun,u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,
          diffalg=ReverseDiff.gradient, kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  CASA User-Jacobian"
      a3 += @elapsed (s=optimize(
        cost,
        (grad,p)->adjoint_diffeq_grad(
          grad,p,ODEFunction(fun,jac=jac),u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,
          sensalg=SensitivityAlg(autojacvec=false), kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  CASA AD-Jacobian"
      a4 += @elapsed (s=optimize(
        cost,
        (grad,p)->adjoint_diffeq_grad(
          grad,p,fun,u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,
          sensalg=SensitivityAlg(autojacvec=false), kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  CASA AD-Jv seeding"
      a5 += @elapsed (s=optimize(
        cost,
        (grad,p)->adjoint_diffeq_grad(
          grad,p,fun,u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,
          sensalg=SensitivityAlg(autojacvec=true), kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      @info "  Numerical Differentiation"
      a6 += @elapsed (s=optimize(
        cost,
        (grad,p)->adjoint_diff_grad(
          grad,p,fun,u0,tspan,data,t; saveat=t, alg=alg, save_everystep=save_everystep,
          diffalg=DiffEqDiffTools.finite_difference_gradient, kwargs...),
        lower, upper, p0, (Fminbox(inner_optimizer)), opt); @test Optim.converged(s));
      if dropfirst && i == 1
        t1, t2, t3, t4, t5, t6 = zeros(6)
        a1, a2, a3, a4, a5, a6 = zeros(6)
      end
    end
    num = dropfirst ? iter-1 : iter
    [t1, t2, t3, t4, t5, t6] ./ num, [a1, a2, a3, a4, a5, a6] ./ num
  end
end