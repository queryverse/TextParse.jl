using Documenter, TextParse

deploydocs(
    repo = "github.com/shashi/TextParse.jl.git",
    deps   = Deps.pip("mkdocs"),
)
