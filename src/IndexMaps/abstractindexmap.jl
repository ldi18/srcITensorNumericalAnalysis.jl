using Base: Base
using Dictionaries: Dictionary, set!
using ITensors: ITensors, Index, dim
using ITensorNetworks: IndsNetwork, vertex_data

abstract type AbstractIndexMap{VB,VD} end

#These functions need to be defined on the concrete type for implementation
index_digit(imap::AbstractIndexMap) = not_implemented()
index_dimension(imap::AbstractIndexMap) = not_implemented()
Base.copy(imap::AbstractIndexMap) = not_implemented()
index_value_to_scalar(imap::AbstractIndexMap, ind::Index, value::Int) = not_implemented()
ITensors.inds(imap::AbstractIndexMap) = not_implemented()
ind(imap::AbstractIndexMap, args...) = not_implemented()
scalartype(imap::AbstractIndexMap) = not_implemented()
function calculate_ind_values(
  imap::AbstractIndexMap, xs::Vector, dims::Vector{Int}; kwargs...
)
  return not_implemented()
end
grid_points(imap::AbstractIndexMap, N::Int, d::Int) = not_implemented()

dimension(imap::AbstractIndexMap) = maximum(collect(values(index_dimension(imap))))
dimension(imap::AbstractIndexMap, ind::Index) = index_dimension(imap)[ind]
dimensions(imap::AbstractIndexMap, inds::Vector{Index}) = dimension.(inds)
digit(imap::AbstractIndexMap, ind::Index) = index_digit(imap)[ind]
digits(imap::AbstractIndexMap, inds::Vector{Index}) = digit.(inds)

function index_values_to_scalars(imap::AbstractIndexMap, ind::Index)
  return [index_value_to_scalar(imap, ind, i) for i in 0:(dim(ind) - 1)]
end

function dimension_inds(imap::AbstractIndexMap, dim::Int)
  return collect(filter(i -> index_dimension(imap)[i] == dim, keys(index_dimension(imap))))
end

function calculate_p(imap::AbstractIndexMap, input::Vector{<:Pair{<:Index,<:Int}})
  ndim = dimension(imap)
  out = zeros(scalartype(imap), ndim)
  for (ind, value) in input
    d = dimension(imap, ind)
    out[d] += index_value_to_scalar(imap, ind, value - 1)
  end
  length(out) == 1 && return first(out)
  return out
end

function calculate_p(
  imap::AbstractIndexMap,
  ind_to_ind_value_map::Dictionary,
  dims::Vector{Int}=[i for i in 1:dimension(imap)],
)
  out = Number[]
  for d in dims
    indices = filter(i -> dimension(imap, i) == d, keys(ind_to_ind_value_map))
    push!(
      out,
      sum([index_value_to_scalar(imap, ind, ind_to_ind_value_map[ind]) for ind in indices]),
    )
  end
  length(out) == 1 && return first(out)
  return out
end

function calculate_p(imap::AbstractIndexMap, ind_to_ind_value_map, dim::Int)
  return calculate_p(imap, ind_to_ind_value_map, [dim])
end

function set_ind_values!(
  ind_to_ind_value_map::Dictionary, imap::AbstractIndexMap, sorted_inds::Vector, x::Number
)
  x_rn = copy(x)
  for ind in sorted_inds
    ind_val = dim(ind) - 1
    ind_set = false
    while !ind_set
      if x_rn >= abs(index_value_to_scalar(imap, ind, ind_val))
        set!(ind_to_ind_value_map, ind, ind_val)
        x_rn -= abs(index_value_to_scalar(imap, ind, ind_val))
        ind_set = true
      else
        ind_val -= 1
      end
    end
  end
end

function calculate_ind_values(imap::AbstractIndexMap, x::Number, dim::Int=1; kwargs...)
  return calculate_ind_values(imap, [x], [dim]; kwargs...)
end
function calculate_ind_values(imap::AbstractIndexMap, xs::Vector; kwargs...)
  return calculate_ind_values(imap, xs, [i for i in 1:length(xs)]; kwargs...)
end

function grid_points(imap::AbstractIndexMap, d::Int)
  dims = dim.(dimension_inds(imap, d))
  @assert all(y -> y == first(dims), dims)
  base = first(dims)
  L = length(dimension_inds(imap, d))
  return grid_points(imap, base^L, d)
end
