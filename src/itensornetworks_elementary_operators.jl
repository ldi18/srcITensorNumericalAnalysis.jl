using Graphs: is_tree
using NamedGraphs: undirected_graph
using ITensors:
  sim,
  OpSum,
  siteinds,
  noprime,
  truncate,
  replaceinds!,
  delta,
  add!,
  prime,
  noprime!,
  contract
using ITensorNetworks: IndsNetwork, ITensorNetwork, TTN, TreeTensorNetwork, combine_linkinds

function plus_shift_ttn(s::IndsNetwork, bit_map; dimension=default_dimension())
  @assert is_tree(s)
  ttn_op = OpSum()
  dim_vertices = vertices(bit_map, dimension)
  L = length(dim_vertices)

  string_site = [("S+", vertex(bit_map, dimension, L))]
  add!(ttn_op, 1.0, "S+", vertex(bit_map, dimension, L))
  for i in L:-1:2
    pop!(string_site)
    push!(string_site, ("S-", vertex(bit_map, dimension, i)))
    push!(string_site, ("S+", vertex(bit_map, dimension, i - 1)))
    add!(ttn_op, 1.0, (string_site...)...)
  end

  return TTN(ttn_op, s; algorithm="svd")
end

function minus_shift_ttn(s::IndsNetwork, bit_map; dimension=default_dimension())
  @assert is_tree(s)
  ttn_op = OpSum()
  dim_vertices = vertices(bit_map, dimension)
  L = length(dim_vertices)

  string_site = [("S-", vertex(bit_map, dimension, L))]
  add!(ttn_op, 1.0, "S-", vertex(bit_map, dimension, L))
  for i in L:-1:2
    pop!(string_site)
    push!(string_site, ("S+", vertex(bit_map, dimension, i)))
    push!(string_site, ("S-", vertex(bit_map, dimension, i - 1)))
    add!(ttn_op, 1.0, (string_site...)...)
  end

  return TTN(ttn_op, s; algorithm="svd")
end

function no_shift_ttn(s::IndsNetwork)
  ttn_op = OpSum()
  string_site_full = [("I", v) for v in vertices(s)]
  add!(ttn_op, 1.0, (string_site_full...)...)
  return TTN(ttn_op, s; algorithm="svd")
end

function stencil(
  s::IndsNetwork,
  bit_map,
  shifts::Vector{Float64},
  delta_power::Int64;
  dimension=default_dimension(),
  truncate_kwargs...,
)
  @assert length(shifts) == 3
  plus_shift = first(shifts) * plus_shift_ttn(s, bit_map; dimension)
  minus_shift = last(shifts) * minus_shift_ttn(s, bit_map; dimension)
  no_shift = shifts[2] * no_shift_ttn(s)

  stencil_op = plus_shift + minus_shift + no_shift
  stencil_op = truncate(stencil_op; truncate_kwargs...)

  for v in vertices(bit_map, dimension)
    stencil_op[v] = (2^delta_power) * stencil_op[v]
  end

  return truncate(stencil_op; truncate_kwargs...)
end

function laplacian_operator(s::IndsNetwork, bit_map; kwargs...)
  return stencil(s, bit_map, [1.0, -2.0, 1.0], 2; kwargs...)
end

function derivative_operator(s::IndsNetwork, bit_map; kwargs...)
  return 0.5 * stencil(s, bit_map, [1.0, 0.0, -1.0], 1; kwargs...)
end

function apply_gx_operator(gx::ITensorNetworkFunction)
  gx = copy(gx)
  operator = itensornetwork(gx)
  s = siteinds(operator)
  for v in vertices(operator)
    sind = s[v]
    sindsim = sim(sind)
    operator[v] = replaceinds!(operator[v], sind, sindsim)
    operator[v] = operator[v] * delta(vcat(sind, sindsim, sind'))
  end
  return operator
end

function multiply(gx::ITensorNetworkFunction, fx::ITensorNetworkFunction)
  @assert vertices(gx) == vertices(fx)
  fx, fxgx = copy(fx), copy(gx)
  s = siteinds(fxgx)
  for v in vertices(fxgx)
    ssim = sim(s[v])
    temp_tensor = replaceinds!(fx[v], s[v], ssim)
    fxgx[v] = noprime!(fxgx[v] * delta(s[v], s[v]', ssim) * temp_tensor)
  end

  return combine_linkinds(fxgx)
end

function multiply(
  gx::ITensorNetworkFunction,
  fx::ITensorNetworkFunction,
  hx::ITensorNetworkFunction,
  fs::ITensorNetworkFunction...,
)
  return multiply(multiply(gx, fx), hx, fs...)
end

Base.:*(fs::ITensorNetworkFunction...) = multiply(fs...)

function operate(
  operator::TreeTensorNetwork, ψ::ITensorNetworkFunction; truncate_kwargs=(;), kwargs...
)
  ψ_tn = TTN(itensornetwork(ψ))
  ψO_tn = noprime(contract(operator, ψ_tn; init=prime(copy(ψ_tn)), kwargs...))
  ψO_tn = truncate(ψO_tn; truncate_kwargs...)

  return ITensorNetworkFunction(ITensorNetwork(ψO_tn), bit_map(ψ))
end

function operate(operator::ITensorNetwork, ψ::ITensorNetworkFunction; kwargs...)
  return operate(TTN(operator), ψ; kwargs...)
end

function operate(
  operators::Vector{TreeTensorNetwork{V}}, ψ::ITensorNetworkFunction; kwargs...
) where {V}
  ψ = copy(ψ)
  for op in operators
    ψ = operate(op, ψ; kwargs...)
  end
  return ψ
end

function operate(
  operators::Vector{ITensorNetwork{V}}, ψ::ITensorNetworkFunction; kwargs...
) where {V}
  return operate(TTN.(operators), ψ; kwargs...)
end
