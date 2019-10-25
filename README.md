# TextParse

[![Tests Status](https://travis-ci.org/JuliaComputing/TextParse.jl.svg?branch=master)](https://travis-ci.org/JuliaComputing/TextParse.jl?branch=master)
[![Coverage Status](https://coveralls.io/repos/github/JuliaComputing/TextParse.jl/badge.svg?branch=master)](https://coveralls.io/github/JuliaComputing/TextParse.jl?branch=master)
[![codecov](https://codecov.io/gh/juliacomputing/TextParse.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/juliacomputing/TextParse.jl)

TextParse uses Julia's generated functions to generate efficient specialized parsers for text files. Right now, there is a good set of features for reading CSV files (see [the documentation](https://JuliaComputing.github.io/TextParse.jl/stable)). Parsing packages can use TextParse as a framework for implementing parsers for other formats.

## Related packages
- [CSV.jl](https://github.com/JuliaData/CSV.jl) - Package for reading CSV files into [Tables](https://github.com/JuliaData/Tables.jl) API. It loads the data into a `DataFrame`. TextParse tries to be minimal and returns a tuple of vectors as the output of `csvread` and adds useful features such as parsing string columns as PooledArrays.
- [CSVFiles.jl](https://github.com/davidanthoff/CSVFiles.jl) - Package for reading CSV via the [FileIO.jl](https://github.com/JuliaIO/FileIO.jl) API into any [IterableTables.jl](https://github.com/davidanthoff/IterableTables.jl) sink. The package uses [TextParse.jl](https://github.com/JuliaComputing/TextParse.jl) for parsing.


[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaComputing.github.io/TextParse.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaComputing.github.io/TextParse.jl/dev)
