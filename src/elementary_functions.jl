using Graphs: nv, vertices, edges, neighbors
using NamedGraphs: NamedEdge, AbstractGraph, a_star
using NamedGraphs.GraphsExtensions:
  random_bfs_tree, rem_edges, add_edges, leaf_vertices, undirected_graph
using ITensors: dim, commoninds
using ITensorNetworks: IndsNetwork, linkinds, underlying_graph

default_c_value() = 1.0
default_a_value() = 0.0
default_k_value() = 1.0
default_nterms() = 20
default_dimension() = 1

"""Build a representation of the function f(x,y,z,...) = c, with flexible choice of linkdim"""
function const_itensornetwork(s::IndsNetworkMap; c=default_c_value(), linkdim::Int=1)
  ψ = random_itensornetwork(s; link_space=linkdim)
  c = c < 0 ? (Complex(c) / linkdim)^Number(1.0 / nv(s)) : (c / linkdim)^Number(1.0 / nv(s))
  for v in vertices(ψ)
    sinds = inds(s, v)
    virt_inds = setdiff(inds(ψ[v]), sinds)
    ψ[v] = c * c_tensor(sinds, virt_inds)
  end

  return ψ
end

"""Construct the product state representation of the exp(kx+a) 
function for x ∈ [0,1] as an ITensorNetworkFunction, along the specified dim"""
function exp_itensornetwork(
  s::IndsNetworkMap;
  k=default_k_value(),
  a=default_a_value(),
  c=default_c_value(),
  dimension::Int=default_dimension(),
)
  ψ = const_itensornetwork(s)
  Lx = length(dimension_vertices(ψ, dimension))
  for v in dimension_vertices(ψ, dimension)
    sinds = inds(s, v)
    linds = setdiff(inds(ψ[v]), sinds)
    ψ[v] = prod([
      ITensor(exp.(k * index_values_to_scalars(s, sind)), sind) for sind in sinds
    ])
    ψ[v] = ψ[v] * exp(a / Lx) * delta(linds)
  end

  ψ[first(dimension_vertices(ψ, dimension))] *= c

  return ψ
end

"""Construct the bond dim 2 representation of the cosh(kx+a) function for x ∈ [0,1] as an ITensorNetwork, using an IndsNetwork which 
defines the network geometry. Vertex map provides the ordering of the sites as bits"""
function cosh_itensornetwork(
  s::IndsNetworkMap;
  k=default_k_value(),
  a=default_a_value(),
  c=default_c_value(),
  dimension::Int=default_dimension(),
)
  ψ1 = exp_itensornetwork(s; a, k, c=0.5 * c, dimension)
  ψ2 = exp_itensornetwork(s; a=-a, k=-k, c=0.5 * c, dimension)

  return ψ1 + ψ2
end

"""Construct the bond dim 2 representation of the sinh(kx+a) function for x ∈ [0,1] as an ITensorNetwork, using an IndsNetwork which 
defines the network geometry. Vertex map provides the ordering of the sites as bits"""
function sinh_itensornetwork(
  s::IndsNetworkMap;
  k=default_k_value(),
  a=default_a_value(),
  c=default_c_value(),
  dimension::Int=default_dimension(),
)
  ψ1 = exp_itensornetwork(s; a, k, c=0.5 * c, dimension)
  ψ2 = exp_itensornetwork(s; a=-a, k=-k, c=-0.5 * c, dimension)

  return ψ1 + ψ2
end

"""Construct the bond dim n representation of the tanh(kx+a) function for x ∈ [0,1] as an ITensorNetwork, using an IndsNetwork which 
defines the network geometry. Vertex map provides the ordering of the sites as bits"""
function tanh_itensornetwork(
  s::IndsNetworkMap;
  k=default_k_value(),
  a=default_a_value(),
  c=default_c_value(),
  nterms::Int=default_nterms(),
  dimension::Int=default_dimension(),
)
  ψ = const_itensornetwork(s)
  for n in 1:nterms
    ψt = exp_itensornetwork(s; a=-2 * n * a, k=-2 * k * n, dimension)
    ψt[first(dimension_vertices(ψ, dimension))] *= 2 * ((-1)^n)
    ψ = ψ + ψt
  end

  ψ[first(dimension_vertices(ψ, dimension))] *= c

  return ψ
end

"""Construct the bond dim 2 representation of the cos(kx+a) function for x ∈ [0,1] as an ITensorNetwork, using an IndsNetwork which 
defines the network geometry. Vertex map provides the ordering of the sites as bits"""
function cos_itensornetwork(
  s::IndsNetworkMap;
  k=default_k_value(),
  a=default_a_value(),
  c=default_c_value(),
  dimension::Int=default_dimension(),
)
  ψ1 = exp_itensornetwork(s; a=a * im, k=k * im, c=0.5 * c, dimension)
  ψ2 = exp_itensornetwork(s; a=-a * im, k=-k * im, c=0.5 * c, dimension)

  return ψ1 + ψ2
end

"""Construct the bond dim 2 representation of the sin(kx+a) function for x ∈ [0,1] as an ITensorNetwork, using an IndsNetwork which 
defines the network geometry. Vertex map provides the ordering of the sites as bits"""
function sin_itensornetwork(
  s::IndsNetworkMap;
  k=default_k_value(),
  a=default_a_value(),
  c=default_c_value(),
  dimension::Int=default_dimension(),
)
  ψ1 = exp_itensornetwork(s; a=a * im, k=k * im, c=-0.5 * im * c, dimension)
  ψ2 = exp_itensornetwork(s; a=-a * im, k=-k * im, c=0.5 * im * c, dimension)

  return ψ1 + ψ2
end

"""Build a representation of the function f(x) = sum_{i=0}^{n}coeffs[i+1]*(x)^{i} on the graph structure specified
by indsnetwork"""
function polynomial_itensornetwork(
  s::IndsNetworkMap,
  coeffs::Vector;
  dimension::Int=default_dimension(),
  k=default_k_value(),
  c=default_c_value(),
)
  n = length(coeffs)
  n == 1 && return const_itn(s; c=first(coeffs))

  coeffs = [c * (k^(i - 1)) for (i, c) in enumerate(coeffs)]
  #First treeify the index network (ignore edges that form loops)
  _s = indsnetwork(s)
  g = underlying_graph(_s)
  g_tree = undirected_graph(random_bfs_tree(g, first(vertices(g))))
  s_tree = add_edges(rem_edges(_s, edges(g)), edges(g_tree))
  s_tree = IndsNetworkMap(s_tree, indexmap(s))
  eltype = is_real(s) ? Float64 : ComplexF64

  ψ = const_itensornetwork(s_tree; linkdim=n)
  dim_vertices = dimension_vertices(ψ, dimension)
  source_vertex = first(dim_vertices)

  for v in dim_vertices
    sinds = inds(s_tree, v)
    if v != source_vertex
      e = get_edge_toward_vertex(g_tree, v, source_vertex)
      betaindex = only(commoninds(ψ, e))
      alphas = setdiff(inds(ψ[v]), [sinds; betaindex])
      ψ[v] = Q_N_tensor(
        eltype,
        length(neighbors(g_tree, v)),
        sinds,
        alphas,
        betaindex,
        index_values_to_scalars.((s_tree,), sinds),
      )
    elseif v == source_vertex
      betaindex = Index(n, "DummyInd")
      alphas = setdiff(inds(ψ[v]), sinds)
      ψv = Q_N_tensor(
        eltype,
        length(neighbors(g_tree, v)) + 1,
        sinds,
        alphas,
        betaindex,
        index_values_to_scalars.((s_tree,), sinds),
      )
      ψ[v] = ψv * ITensor(coeffs, betaindex)
    end
  end

  ψ[first(dim_vertices)] *= c

  #Put the transfer tensors in, these are special tensors that
  # go on the digits (sites) that don't correspond to the desired dimension
  for v in setdiff(vertices(ψ), dim_vertices)
    sinds = inds(s_tree, v)
    e = get_edge_toward_vertex(g_tree, v, source_vertex)
    betaindex = only(commoninds(ψ, e))
    alphas = setdiff(inds(ψ[v]), [sinds; betaindex])
    ψ[v] = transfer_tensor(sinds, betaindex, alphas)
  end

  return ψ
end

function random_itensornetwork(s::IndsNetworkMap; kwargs...)
  return ITensorNetworkFunction(random_tensornetwork(indsnetwork(s); kwargs...), s)
end

"Create a product state of a given bit configuration"
function delta_xyz(s::IndsNetworkMap, xs::Vector, dimensions::Vector{Int}; kwargs...)
  ind_to_ind_value_map = calculate_ind_values(s, xs, dimensions)
  tn = ITensorNetwork(v -> string(ind_to_ind_value_map[only(s[v])]), indsnetwork(s))
  return ITensorNetworkFunction(tn, s)
end

function delta_xyz(s::IndsNetworkMap, xs::Vector; kwargs...)
  return delta_xyz(s, xs, [i for i in 1:length(xs)]; kwargs...)
end

"Create a product state of a given bit configuration of a 1D function"
function delta_x(s::IndsNetworkMap, x::Number, kwargs...)
  @assert dimension(s) == 1
  return delta_xyz(s, [x], [1]; kwargs...)
end

const const_itn = const_itensornetwork
const poly_itn = polynomial_itensornetwork
const cosh_itn = cosh_itensornetwork
const sinh_itn = sinh_itensornetwork
const tanh_itn = tanh_itensornetwork
const exp_itn = exp_itensornetwork
const sin_itn = sin_itensornetwork
const cos_itn = cos_itensornetwork
const rand_itn = random_itensornetwork
