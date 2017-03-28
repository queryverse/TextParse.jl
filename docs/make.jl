using Documenter, TextParse

deploydocs(
    repo = "github.com/JuliaComputing/TextParse.jl.git",
    deps   = Deps.pip("mkdocs"),
)
