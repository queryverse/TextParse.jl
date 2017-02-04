if VERSION < v"0.6.0-dev"
    include("fast-dates.jl")

    include("Str.jl")
else
    const Str = String
end
