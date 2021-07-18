import Rocket as R

function stateful_flatmap(::Type{ElemT}, fn::Function, seed::SeedT) where { ElemT, SeedT }
    scan_fn(data, (_, state)) = fn(data, state)

    R.scan(Tuple{Vector{<:ElemT}, SeedT}, scan_fn, (ElemT[], seed)) |>
        R.concat_map(ElemT, ((val, _),) -> R.from(val))
end

