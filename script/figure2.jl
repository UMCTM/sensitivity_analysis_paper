using Plots; pgfplots()
eval.(Meta.parse.(split(String(read(joinpath(@__DIR__, "..", "bruss_scaling_data.txt"))), '\n')))

n_to_param(n) = 4n^2

plt = plot(title="Sensitivity Scaling on Brusselator");
plot!(plt, n_to_param.(forwarddiffn), forwarddiff, lab="Forward-Mode DSAAD");
plot!(plt, n_to_param.(reversediffn), reversediff, lab="Reverse-Mode DSAAD");
plot!(plt, n_to_param.(csan), csa, lab="CASA AD-Jacobian");
plot!(plt, n_to_param.(csaseedn), csaseed, lab=raw"CASA AD-$v^{T}J$ seeding");
plot!(plt, n_to_param.(numdiffn), numdiff, lab="Numerical Differentiation");
plot!(plt, lw = 5, legend=:bottomright);
xaxis!(plt, "Number of Parameters", :log10);
yaxis!(plt, "Runtime (s)", :log10);
savefig(plt, "figure2.pdf")
