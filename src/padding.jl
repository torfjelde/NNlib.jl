export pad_constant, pad_repeat, pad_reflect, pad_zeros

"""
    pad_zeros(x, pad::Tuple; [dims])
    pad_zeros(x, pad::Int; [dims])

Pad the array `x` with zeros.
Equivalent to [`pad_constant`](@ref) with the constant equal to 0. 
"""
pad_zeros(x::AbstractArray, pad; dims = :) =
  pad_constant(x, pad, 0; dims = dims)

"""
    pad_constant(x, pad::Tuple, val = 0; [dims = :])
    pad_constant(x, pad::Int, val = 0; [dims = :])

Pad the array `x` with the constant value `val`.

`pad` can be a tuple of integers `(l1, r1, ..., ln, rn)`
of some length `2n` that specifies the left and right padding size
for each of the dimensions in `dims`. 
If supplied with a tuple of length `n`  instead, it applies symmetric padding.
If `dims` is not given, it defaults to all dimensions.

For integer `pad` input instead, it is applied on both sides
on every dimension in `dims`.

See also [`pad_reflect`](@ref) and [`pad_repeat`](@ref).

```jldoctest

julia> r = reshape(1:4, 2, 2)
2×2 reshape(::UnitRange{Int64}, 2, 2) with eltype Int64:
 1  3
 2  4

julia> pad_constant(r, (1, 2, 3, 4), 8)
5×9 Matrix{Int64}:
 8  8  8  8  8  8  8  8  8
 8  8  8  1  3  8  8  8  8
 8  8  8  2  4  8  8  8  8
 8  8  8  8  8  8  8  8  8
 8  8  8  8  8  8  8  8  8

julia> pad_constant(r, 1, 8)
5×9 Matrix{Int64}:
 8  8  8  8
 8  1  3  8
 8  2  4  8
 8  8  8  8

julia> r = reshape(1:27, 3, 3, 3)
3×3×3 reshape(::UnitRange{Int64}, 3, 3, 3) with eltype Int64:
[:, :, 1] =
 1  4  7
 2  5  8
 3  6  9

[:, :, 2] =
 10  13  16
 11  14  17
 12  15  18

[:, :, 3] =
 19  22  25
 20  23  26
 21  24  27

julia> pad_constant(r, (2,1), dims = 1) # assymetric padding
6×3×3 Array{Int64,3}:
[:, :, 1] =
 0  0  0
 0  0  0
 1  4  7
 2  5  8
 3  6  9
 0  0  0

[:, :, 2] =
  0   0   0
  0   0   0
 10  13  16
 11  14  17
 12  15  18
  0   0   0

[:, :, 3] =
  0   0   0
  0   0   0
 19  22  25
 20  23  26
 21  24  27
  0   0   0

julia> pad_constant(r, (2,1, 3), dims = (1,2)) # padding must always be either the same length as dims, or double it
ERROR: ArgumentError: Could not parse padding (2, 1, 3) and dims (1, 2)
Stacktrace:
[...]
```
"""
pad_constant(x::AbstractArray{T,N}, pad::Int, val = 0; dims = :) where {T,N} =
  pad_constant(x, gen_pad(pad, dims isa Colon ? dims : (dims...,), N), val)
pad_constant(x::AbstractArray{T,N}, pad::Tuple, val = 0; dims = :) where {T,N} =
  pad_constant(x, gen_pad(pad, dims isa Colon ? dims : (dims...,), N), val)

function pad_idx(pad, dims, N)
  is = zip( (2 .* dims) .- 1, (2 .* dims))
end

@inline tuplejoin(x) = x
@inline tuplejoin(x, y) = (x..., y...)
@inline tuplejoin(x, y, z...) = tuplejoin(tuplejoin(x, y), z...)

function pad_zeros_tuple(pad::NTuple{L,Int}, N) where L
  ntuple(2N) do i
    if i <= L
      pad[i]
    else
      0
    end
  end
end

gen_pad(pad::Int, dims, N) = gen_pad(ntuple(_ -> pad, length(dims)), dims, N)
gen_pad(pad::Int, dims::Colon, N) = ntuple(_ -> pad, 2N)
gen_pad(pad, dims::Colon, N) = gen_pad(pad, ntuple(identity, N), N)
gen_pad(pad::Int, dims::Int, N) = gen_pad((pad,pad), (dims,), N)
function gen_pad(pad::NTuple{L,Int}, dims::NTuple{D,Int}, N) where {L,D}
  ntuple(N) do d
   if d in dims
     if L == D
       ix = findfirst(==(d), dims)
       (pad[ix], pad[ix])
     elseif L == 2D
       ix = findfirst(==(d), dims)
       (pad[2ix - 1], pad[2ix])
     else
       throw(ArgumentError("Could not parse padding $pad and dims $dims"))
     end
   else
     (0,0)
   end

  end
end


# Expects length(pad) == 2M
function pad_constant(x::AbstractArray{T,M}, pad::NTuple{N,Tuple{Int,Int}}, val = 0) where {T,M,N}
  p = pad_zeros_tuple(tuplejoin(reverse.(pad)...), M)
  sz, c = size_and_center(x, p)
  res = fill!(similar(x, sz...), val)
  res[c..., ntuple(_ -> Colon(), Val(M - 2))...] = x
  res
end

function size_and_center(x, pad::NTuple{N,Int}) where N
  ds = 1:2:N
  dst = ntuple(i -> ds[i], N÷2)
  sz = map(i -> pad[i] + pad[i+1], dst) .+ size(x)
  center = broadcast((x,y) -> x .+ y, axes(x), pad[2:2:end]::NTuple{N÷2,Int})
  sz, center
end

function rrule(::typeof(pad_constant), x::AbstractArray{T,N},
               pad, val; dims = :) where {T,N}
  y = pad_constant(x, pad, val; dims = dims)
  function pad_constant_pullback(Δ)
    p = gen_pad(pad, dims, N)
    outsize, center = size_and_center(x, p)
    (NO_FIELDS, @thunk(Δ[center...]), DoesNotExist(), DoesNotExist(),)
  end
  return y, pad_constant_pullback
end


"""
    pad_repeat(x, pad::Tuple; [dims])
    pad_repeat(x, pad::Int; [dims])
 
Pad the array `x` repeating the values on the border.

`pad` can a tuple of integers `(l1, r1, ..., ln, rn)`
of some length `2n` that specifies the left and right padding size
for each of the dimensions in `dims`. If `dims` is not given, 
it defaults to the first `n` dimensions.

For integer `pad` input instead, it is applied on both sides
on every dimension in `dims`. In this case, `dims` 
defaults to the first `ndims(x)-2` dimensions 
(i.e. excludes the channel and batch dimension). 

See also [`pad_reflect`](@ref) and [`pad_constant`](@ref).

```jldoctest

julia> r = reshape(1:9, 3, 3)
3×3 reshape(::UnitRange{Int64}, 3, 3) with eltype Int64:
 1  4  7
 2  5  8
 3  6  9

julia> pad_repeat(r, (1,2,3,4))
6×10 Matrix{Int64}:
 1  1  1  1  4  7  7  7  7  7
 1  1  1  1  4  7  7  7  7  7
 2  2  2  2  5  8  8  8  8  8
 3  3  3  3  6  9  9  9  9  9
 3  3  3  3  6  9  9  9  9  9
 3  3  3  3  6  9  9  9  9  9
```
"""
function pad_repeat(x::AbstractArray, pad::NTuple{M,Int}; 
                    dims = 1:M÷2) where M
  length(dims) == M ÷ 2 ||
    throw(ArgumentError("The number of dims should be equal to the number of padding dimensions"))
  for (i, d) in enumerate(dims)
    x = pad_repeat(x, (pad[2i-1], pad[2i]); dims=d)
  end  
  return x
end

function pad_repeat(x::AbstractArray{F,N}, pad::NTuple{2,Int}; 
                    dims::Int = 1) where {F,N}
  lpad, rpad = pad

  xlborder = selectdim(x, dims, 1:1)
  nrepl = ntuple(i -> i == dims ? lpad : 1, N)
  xl = repeat(xlborder, outer = nrepl)

  n = size(x, dims)
  xrborder = selectdim(x, dims, n:n)
  nrepr = ntuple(i -> i == dims ? rpad : 1, N)
  xr = repeat(xrborder, outer = nrepr)

  return cat(xl, x, xr, dims = dims)
end

"""
    pad_reflect(x, pad::Tuple; [dims])
    pad_reflect(x, pad::Int; [dims])

Pad the array `x` reflecting its values across the border.

`pad` can a tuple of integers `(l1, r1, ..., ln, rn)`
of some length `2n` that specifies the left and right padding size
for each of the dimensions in `dims`. If `dims` is not given, 
it defaults to the first `n` dimensions.

For integer `pad` input instead, it is applied on both sides
on every dimension in `dims`. In this case, `dims` 
defaults to the first `ndims(x)-2` dimensions 
(i.e. excludes the channel and batch dimension).

See also [`pad_repeat`](@ref) and [`pad_constant`](@ref).

```jldoctest

julia> r = reshape(1:9, 3, 3)
3×3 reshape(::UnitRange{Int64}, 3, 3) with eltype Int64:
 1  4  7
 2  5  8
 3  6  9

julia> pad_reflect(r, (1,2,1,2))
6×6 Matrix{Int64}:
 5  2  5  8  5  2
 4  1  4  7  4  1
 5  2  5  8  5  2
 6  3  6  9  6  3
 5  2  5  8  5  2
 4  1  4  7  4  1
```
"""
function pad_reflect(x::AbstractArray, pad::NTuple{M,Int}; 
                     dims=1:M÷2) where M
  length(dims) == M ÷ 2 ||
    throw(ArgumentError("The number of dims should be equal to the number of padding dimensions"))
  for (i, d) in enumerate(dims)
    x = pad_reflect(x, (pad[2i-1], pad[2i]); dims = d)
  end  
  return x
end

function pad_reflect(x::AbstractArray{F,N}, pad::NTuple{2,Int}; 
                     dims::Int = 1) where {F,N}
  lpad, rpad = pad
  
  n = size(x, dims)
  xl = selectdim(x, dims, lpad+1:-1:2)
  xr = selectdim(x, dims, n-1:-1:n-rpad)
  # Alternative selection, not sure which is faster...
  # xl = reverse(selectdim(x, dims, 2:lpad+1), dims)
  # xr = reverse(selectdim(x, dims, n-rpad:n-1), dims)
  return cat(xl, x, xr, dims = dims)
end

# convenience methods for symmetric and homogeneous padding
pad_repeat(x::AbstractArray{F,N}, pad::Int; dims=1:N-2) where {F,N} =
  pad_repeat(x, ntuple(_ -> pad, 2length(dims)); dims = dims)
pad_reflect(x::AbstractArray{F,N}, pad::Int; dims=1:N-2) where {F,N} =
  pad_reflect(x, ntuple(_ -> pad, 2length(dims)); dims = dims)
