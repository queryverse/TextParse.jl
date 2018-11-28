module TextParse

using CodecZlib, WeakRefStrings, Dates, Nullables, DoubleFloats

export MyStringType

include("mystringtype.jl")
include("lib/compat.jl")
include("util.jl")
include("field.jl")
include("record.jl")

include("utf8optimizations.jl")

include("guesstype.jl")
include("csv.jl")

end # module
