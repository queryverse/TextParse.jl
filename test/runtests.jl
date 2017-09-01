using TextParse

import TextParse: tryparsenext, unwrap, failedat, AbstractToken, LocalOpts
using Base.Test

# dumb way to compare two AbstractTokens
Base.:(==){T<:AbstractToken}(a::T, b::T) = string(a) == string(b)

import TextParse: eatnewlines
@testset "eatnewlines" begin
    @test eatnewlines("\n\r\nx") == (4, 2)
    @test eatnewlines("x\n\r\nx") == (1, 0)
end


import TextParse: getlineend
@testset "getlineend" begin
    @test getlineend("\nx") == 0
    @test getlineend("x\nx") == 1
    @test getlineend("x\ny", 2) == 1
    @test getlineend("x\nyz", 3) == 4
end


import TextParse: fromtype, Percentage
@testset "Float parsing" begin

    @test tryparsenext(fromtype(Float64), "1", 1, 1) |> unwrap == (1.0, 2)
    @test tryparsenext(fromtype(Float64), "12", 1, 2) |> unwrap == (12.0, 3)
    @test tryparsenext(fromtype(Float64), ".1", 1, 2) |> unwrap == (0.1, 3)
    @test tryparsenext(fromtype(Float64), "1.1", 1, 3) |> unwrap == (1.1, 4)
    @test tryparsenext(fromtype(Float32), "1.", 1, 2) |> unwrap == (1f0,3)
    @test tryparsenext(fromtype(Float64), "-1.1", 1, 4) |> unwrap == (-1.1,5)
    @test tryparsenext(fromtype(Float64), "-1.0e-12", 1, 8) |> unwrap == (-1.0e-12,9)
    @test tryparsenext(fromtype(Float64), "-1e-12") |> unwrap == (-1.0e-12,7)
    @test tryparsenext(fromtype(Float64), "-1.0E-12", 1, 8) |> unwrap == (-1.0e-12,9)
    @test tryparsenext(Percentage(), "33%") |> unwrap == (.33,4)
    @test tryparsenext(Percentage(), "3.3%") |> unwrap == (.033,5)
end


import TextParse: StringToken
using WeakRefStrings
@testset "String parsing" begin

    # default options
    @test tryparsenext(StringToken(String), "") |> unwrap == ("", 1)
    x = "x"
    @test tryparsenext(StringToken(WeakRefString), WeakRefString(pointer(x), 1)) |> unwrap == ("x", 2)
    @test tryparsenext(StringToken(String), "x") |> unwrap == ("x", 2)
    @test tryparsenext(StringToken(String), "x ") |> unwrap == ("x ", 3)
    @test tryparsenext(StringToken(String), " x") |> unwrap == (" x", 3)
    @test tryparsenext(StringToken(String), "x\ny") |> unwrap == ("x", 2)
    @test tryparsenext(StringToken(String), "x,y") |> unwrap == ("x", 2) # test escape

    opts = LocalOpts(',', '"', '"', true, true)
    @test tryparsenext(StringToken(String), "", opts) |> unwrap == ("", 1)
    @test tryparsenext(StringToken(String), "\"\"", opts) |> unwrap == ("\"\"", 3)
    @test tryparsenext(StringToken(String), "x", opts) |> unwrap == ("x", 2)
    # test including new lines
    @test tryparsenext(StringToken(String), "x\ny", opts) |> unwrap == ("x\ny", 4)
    @test tryparsenext(StringToken(String), "\"x\ny\"", opts) |> unwrap == ("\"x\ny\"", 6)

    opts = LocalOpts(',', '"', '"', false, true)
    # test that includequotes option doesn't affect string
    @test tryparsenext(StringToken(String), "\"\"", opts) |> unwrap == ("\"\"", 3)

    opts = LocalOpts(',', '"', '\\', false, false)
    str =  "Owner 2 ”Vicepresident\"\""
    @test tryparsenext(Quoted(String), str) |> unwrap == (str, endof(str)+1)
    str1 =  "\"Owner 2 ”Vicepresident\"\"\""
    @test tryparsenext(Quoted(String,quotechar=Nullable('"'), escapechar=Nullable('"')), str1) |> unwrap == (str, endof(str1)+1)

end


import TextParse: Quoted, NAToken, Unknown
@testset "Quoted string parsing" begin
    opts = LocalOpts(',', '"', '"', true, true)

    @test tryparsenext(Quoted(String), "\"\"") |> unwrap == ("", 3)
    @test tryparsenext(Quoted(String), "\"\" ", opts) |> unwrap == ("", 3)
    @test tryparsenext(Quoted(String), "\"x\"") |> unwrap == ("x", 4)
    @test tryparsenext(Quoted(String, includequotes=true), "\"x\"") |> unwrap == ("\"x\"", 4)
    str2 =  "\"\"\"\""
    @test tryparsenext(Quoted(String), str2, opts) |> unwrap == ("\"\"", endof(str2)+1)
    str1 =  "\"x”y\"\"\""
    @test tryparsenext(Quoted(StringToken(String), required=true), "x\"y\"") |> failedat == 1

    @test tryparsenext(Quoted(String,quotechar=Nullable('"'), escapechar=Nullable('"')), str1) |> unwrap == ("x”y\"\"", endof(str1)+1)
    @test tryparsenext(Quoted(StringToken(String)), "\"x\\\"yz\"") |> unwrap == ("x\\\"yz", 8)
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "1") |> unwrap |> unwrap == (1,2)
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "") |> unwrap |> failedat == 1
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "\"\"") |> unwrap |> failedat == 3
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "\"1\"") |> unwrap |> unwrap == (1, 4)


    @test tryparsenext(Quoted(StringToken(String)), "\"abc\"") |> unwrap == ("abc", 6)
    @test tryparsenext(Quoted(StringToken(String)), "x\"abc\"") |> unwrap == ("x\"abc\"", 7)
    @test tryparsenext(Quoted(StringToken(String)), "\"a\nbc\"") |> unwrap == ("a\nbc", 7)
    @test tryparsenext(Quoted(StringToken(String), required=true), "x\"abc\"") |> failedat == 1
    @test tryparsenext(Quoted(fromtype(Int)), "21") |> unwrap == (21,3)
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "21") |> unwrap |> unwrap == (21,3)
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "") |> unwrap |> failedat == 1
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "\"\"") |> unwrap |> failedat == 3
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "\"21\"") |> unwrap |> unwrap == (21, 5)
    @test isnull(tryparsenext(Quoted(NAToken(Unknown())), " ") |> unwrap |> first)
    opts = LocalOpts(',', '"', '"', false, false)
    @test tryparsenext(Quoted(StringToken(String)), "x,", opts) |> unwrap == ("x", 2)

    # stripspaces
    @test tryparsenext(Quoted(Percentage()), "\" 10%\",", opts) |> unwrap == (0.1, 7)
    @test tryparsenext(Quoted(String), "\" 10%\",", opts) |> unwrap == (" 10%", 7)
end

@testset "NA parsing" begin
    @test tryparsenext(NAToken(fromtype(Float64)), ",") |> unwrap |> failedat == 1 # is nullable
    @test tryparsenext(NAToken(fromtype(Float64)), "X,") |> failedat == 1
    @test tryparsenext(NAToken(fromtype(Float64)), "NA,") |> unwrap |> failedat == 3
    @test tryparsenext(NAToken(fromtype(Float64)), "1.212,") |> unwrap |> unwrap == (1.212, 6)
end

import TextParse: Field
@testset "Field parsing" begin
    f = fromtype(Int)
    @test tryparsenext(Field(f,delim=','), "12,3") |> unwrap == (12, 4)
    @test tryparsenext(Field(f,delim=','), "12 ,3") |> unwrap == (12, 5)
    @test tryparsenext(Field(f,delim=','), " 12 ,3") |> unwrap == (12, 6)
    @test tryparsenext(Field(f,delim='\t'), "12\t3") |> unwrap == (12, 4)
    @test tryparsenext(Field(f,delim='\t'), "12 \t3") |> unwrap == (12, 5)
    @test tryparsenext(Field(f,delim='\t'), " 12 \t 3") |> unwrap == (12, 6)
    @test tryparsenext(Field(f,spacedelim=true), " 12 3") |> unwrap == (12, 5)
    @test tryparsenext(Field(f,spacedelim=true), " 12 3") |> unwrap == (12, 5)
    @test tryparsenext(Field(f,spacedelim=true, ignore_end_whitespace=false), " 12 \t 3") |> unwrap == (12, 5)
    @test tryparsenext(Field(f,ignore_end_whitespace=false, delim=' '), "12 3") |> unwrap == (12, 4)
    @test tryparsenext(Field(f,ignore_end_whitespace=false, delim='\t'), "12 \t3") |> failedat == 3
    @test tryparsenext(Field(f,ignore_end_whitespace=false, delim='\t'), " 12\t 3") |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true, delim='\t'), " 12\n") |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true), " 12") |> unwrap == (12,4)
    @test tryparsenext(Field(f,eoldelim=true, delim='\t'), " 12\n\r\n") |> unwrap == (12,6)
end


import TextParse: Record
@testset "Record parsing" begin
    r=Record((Field(fromtype(Int)), Field(fromtype(UInt)), Field(fromtype(Float64))))
    @test tryparsenext(r, "12,21,21,", 1, 9) |> unwrap == ((12, UInt(21), 21.0), 10)
    @test tryparsenext(r, "12,21.0,21,", 1, 9) |> failedat == 6
    s = "12   ,  21,  21.23,"
    @test tryparsenext(r, s, 1, length(s)) |> unwrap == ((12, UInt(21), 21.23), length(s)+1)
end


import TextParse: UseOne
@testset "UseOne" begin
    f = UseOne((Field(fromtype(Int), delim=';'), Field(fromtype(Float64)), Field(fromtype(Int), eoldelim=true)), 3)
    @test tryparsenext(f, "1; 33.21, 45", 1, 12) |> unwrap == (45, 13)
end

import TextParse: Repeated
@testset "Repeated" begin
    f = Repeated(Field(fromtype(Int), delim=';'), 3)
    @test tryparsenext(f, "1; 33; 45;", 1, 12) |> unwrap == ((1,33,45), 11)

    inp = join(map(string, [1:45;]), "; ") * "; "
    out = ntuple(identity, 45)
    f2 = Repeated(Field(fromtype(Int), delim=';'), 45)
    @test tryparsenext(f2, inp, 1, length(inp)) |> unwrap == (out, length(inp))
    #@benchmark tryparsenext($f2, $inp, 1, length($inp))
end


import TextParse: quotedsplit
@testset "quotedsplit" begin
    opts = LocalOpts(',', '"', '\\', false, false)
    @test quotedsplit("x", opts, false, 1, 1) == ["x"]
    @test quotedsplit("x, y", opts, false, 1, 4) == ["x", "y"]
    @test quotedsplit("\"x\", \"y\"", opts,false, 1, 8) == ["x", "y"]
    @test quotedsplit("\"x\", \"y\"", opts,true, 1, 8) == ["\"x\"", "\"y\""]
    str = """x\nx,"s,", "\\",x" """
    @test quotedsplit(str, opts, false, 3, length(str)) == ["x", "s,", "\\\",x"]
    @test quotedsplit(",", opts, true, 1, 1) == ["", ""]
    @test quotedsplit(", ", opts, false, 1, 2) == ["", ""]
    str = "1, \"x \"\"y\"\" z\", 1"
    qopts = LocalOpts(',', '"', '"', false, false)
    @test quotedsplit(str, qopts,true, 1, endof(str)) == ["1", "\"x \"\"y\"\" z\"", "1"]
end

import TextParse: LocalOpts, readcolnames
@testset "CSV column names" begin
    str1 = """
     a, b,c d, e
    x,1,1,1
    ,1,1,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """

    str2 = """
     a, " b", "c", "d\\" e "
    """
    opts = LocalOpts(',', '"', '\\', false, false)
    @test readcolnames(str1, opts, 1, String[]) == (["a", "b", "c d", "e"], 13)
    @test readcolnames("\n\r$str1", opts, 3, Dict(3=>"x")) == (["a", "b", "x", "e"], 15)
    #@test readcolnames("$str2", opts, 3, Dict(3=>"x")) == (["a", "b", "x", "d\" e"], 24)
end

import TextParse: guesstoken, Unknown, Numeric, DateTimeToken, StrRange
@testset "guesstoken" begin
    # Test null values
    @test guesstoken("", Unknown()) == NAToken(Unknown())
    @test guesstoken("null", Unknown()) == NAToken(Unknown())
    @test guesstoken("", NAToken(Unknown())) == NAToken(Unknown())
    @test guesstoken("null", NAToken(Unknown())) == NAToken(Unknown())

    # Test NA
    @test guesstoken("1", NAToken(Unknown())) == NAToken(Numeric(Int))
    @test guesstoken("1", NAToken(Numeric(Int))) == NAToken(Numeric(Int))
    @test guesstoken("", NAToken(Numeric(Int))) == NAToken(Numeric(Int))
    @test guesstoken("1%", NAToken(Unknown())) == NAToken(Percentage())

    # Test non-null numeric
    @test guesstoken("1", Unknown()) == Numeric(Int)
    @test guesstoken("1", Numeric(Int)) == Numeric(Int)
    @test guesstoken("", Numeric(Int)) == NAToken(Numeric(Int))
    @test guesstoken("1.0", Numeric(Int)) == Numeric(Float64)

    # Test strings
    @test guesstoken("x", Unknown()) == StringToken(StrRange)

    # Test nullable to string
    @test guesstoken("x", NAToken(Unknown())) == StringToken(StrRange)

    # Test string to non-null (short circuit)
    @test guesstoken("1", StringToken(StrRange)) == StringToken(StrRange)

    # Test quoting
    @test guesstoken("\"1\"", Unknown()) == Quoted(Numeric(Int))
    @test guesstoken("\"1\"", Quoted(Numeric(Int))) == Quoted(Numeric(Int))

    # Test quoting with Nullable tokens
    @test guesstoken("\"\"", Quoted(Unknown())) == Quoted(NAToken(Unknown()))
    @test guesstoken("\"\"", Quoted(NAToken(Unknown()))) == Quoted(NAToken(Unknown()))
    @test guesstoken("\"\"", Quoted(Numeric(Int))) == Quoted(NAToken(Numeric(Int)))
    @test guesstoken("\"\"", Unknown()) == Quoted(NAToken(Unknown()))
    @test guesstoken("\"\"", Numeric(Int)) == Quoted(NAToken(Numeric(Int)))
    @test guesstoken("", Quoted(Numeric(Int))) == Quoted(NAToken(Numeric(Int)))
    @test guesstoken("", Quoted(NAToken(Numeric(Int)))) == Quoted(NAToken(Numeric(Int)))
    @test guesstoken("1", Quoted(NAToken(Numeric(Int)))) == Quoted(NAToken(Numeric(Int)))
    @test guesstoken("\"1\"", Quoted(NAToken(Numeric(Int)))) == Quoted(NAToken(Numeric(Int)))

    # Test DateTime detection:
    tok = guesstoken("2016-01-01 10:10:10.10", Unknown())
    @test tok == DateTimeToken(DateTime, dateformat"yyyy-mm-dd HH:MM:SS.s")
    @test guesstoken("2016-01-01 10:10:10.10", tok) == tok
    @test guesstoken("2016-01-01 10:10:10.10", Quoted(NAToken(Unknown()))) == Quoted(NAToken(tok))
end

import TextParse: guesscolparsers
@testset "CSV type detect" begin
    str1 = """
     a, b,c d, e
    x,1,1,1
    x,1,1,1
    x,1,1.,1
    x y,1.0,1,
    ,1.0,,1
    """
    opts = LocalOpts(',', '"', '\\', false, false)
    _, pos = readcolnames(str1, opts, 1, String[])
    testtill(i, colparsers=[]) = guesscolparsers(str1, String[], opts, pos, i, colparsers)
    @test testtill(0) |> first == Any[]
    @test testtill(1) |> first == map(fromtype, [StrRange, Int, Int, Int])
    @test testtill(2) |> first == map(fromtype, [StrRange, Int, Int, Int])
    @test testtill(3) |> first == map(fromtype, [StrRange, Int, Float64, Int])
    @test testtill(4) |> first == vcat(map(fromtype, [StrRange, Float64, Float64]),
                                       NAToken(fromtype(Int)))
    @test testtill(5) |> first == vcat(map(fromtype, [StrRange, Float64]),
                                       NAToken(fromtype(Float64)),
                                       NAToken(fromtype(Int)))
end


import TextParse: getlineat
@testset "getlineat" begin
    str = "abc\ndefg"
    @test str[getlineat(str,1)] == "abc\n"
    @test str[getlineat(str,4)] == "abc\n"
    @test str[getlineat(str,5)] == "defg"
    @test str[getlineat(str,endof(str))] == "defg"
    @test getlineat("x", 5) == 1:1
end


import TextParse: guessdateformat
@testset "date detection" begin
    @test guessdateformat("2016") |> typeof == DateTimeToken(Date, dateformat"yyyy-mm-dd") |> typeof
    @test guessdateformat("09/09/2016") |> typeof == DateTimeToken(Date, dateformat"mm/dd/yyyy") |> typeof
    @test guessdateformat("24/09/2016") |> typeof == DateTimeToken(Date, dateformat"dd/mm/yyyy") |> typeof
end

@testset "date parsing" begin
    tok = DateTimeToken(DateTime, dateformat"yyyy-mm-dd HH:MM:SS")
    opts = LocalOpts('y', '"', '\\', false, false)
    str = "1970-02-02 02:20:20"
    @test tryparsenext(tok, str, 1, length(str), opts) |> unwrap == (DateTime("1970-02-02T02:20:20"), length(str)+1)
    @test tryparsenext(tok, str*"x", 1, length(str)+1, opts) |> unwrap == (DateTime("1970-02-02T02:20:20"), length(str)+1)
    @test tryparsenext(tok, str[1:end-3]*"x", 1, length(str)-2, opts) |> failedat == length(str)-2
    @test tryparsenext(tok, str[1:end-3]*"y", 1, length(str)-2, opts) |> unwrap == (DateTime("1970-02-02T02:20"), length(str)-2)
end


using NullableArrays
import TextParse: _csvread
@testset "_csvread" begin

    str1 = """
     a, b,c d, e
    x,1,1,1
    ,1,,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    data = ((["x", "","x","x y","x"],
              ones(5),
              NullableArray(ones(5), Bool[0,1,0,0,1]),
              NullableArray(ones(Int,5), Bool[0,0,0,1,0])),
              ["a", "b", "c d", "e"])
    @test isequal(_csvread(str1, ','), data)
    coltype_test1 = _csvread(str1,
                            colparsers=Dict("b"=>Nullable{Float64},
                                          "e"=>Nullable{Float64}))
    coltype_test2 = _csvread(str1,
                            colparsers=Dict(2=>Nullable{Float64},
                                          4=>Nullable{Float64}))

    str2 = """
    x,1,1,1
    ,1,,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    coltype_test3 = _csvread(str2, header_exists=false,
                            colparsers=Dict(2=>Nullable{Float64},
                                          4=>Nullable{Float64}))
    @test eltype(coltype_test1[1][2]) == Nullable{Float64}
    @test eltype(coltype_test1[1][4]) == Nullable{Float64}
    @test eltype(coltype_test2[1][2]) == Nullable{Float64}
    @test eltype(coltype_test2[1][4]) == Nullable{Float64}
    @test eltype(coltype_test3[1][2]) == Nullable{Float64}
    @test eltype(coltype_test3[1][4]) == Nullable{Float64}

    @test isequal(data, _csvread(str1, type_detect_rows=1))
    @test isequal(data, _csvread(str1, type_detect_rows=2))
    @test isequal(data, _csvread(str1, type_detect_rows=3))
    @test isequal(data, _csvread(str1, type_detect_rows=4))
    # But we can't go from a non-string column to a string column
    str3 = """
     a, b,c d, e
    1,1,1,1
    x,1,1,1
    """
    @test_throws TextParse.CSVParseError _csvread(str3, type_detect_rows=1)

    # test growing of columns if prediction is too low
    @test _csvread("x,y\nabcd, defg\n,\n,\n", type_detect_rows=1) ==
        ((String["abcd", "", ""], String["defg", "", ""]), String["x", "y"])

    # #19
    s="""
    x,y,z
    1,1,x
    "2",2,x
    1,2,"x \"\"y\"\""
    """

    res = (([1, 2, 1], [1, 2, 2], String["x", "x", "x \"\"y\"\""]), String["x", "y", "z"])
    @test _csvread(s, type_detect_rows=1, escapechar='"') == res
    @test _csvread(s, type_detect_rows=2, escapechar='"') == res

    @test csvread(IOBuffer("x\n1")) == (([1],),["x"])

    @test _csvread("x\n1\n") == (([1],),["x"])

    # test detection of newlines in fields
    s = """x, y
        abc, def
        g
        hi,jkl
        mno,pqr
        """

    @test _csvread(s, type_detect_rows=1) == ((["abc", "g\nhi", "mno"], ["def", "jkl", "pqr"]), ["x", "y"])
    # test custom na strings
    s = """
    x,y
    1,2
    ?,3
    4,*
    """
    nullness = ([false, true, false], [false, false, true])
    @test map(x->x.isnull, first(_csvread(s, nastrings=["?","*"]))) == nullness
    @test map(x->x.isnull, first(_csvread(s, nastrings=["?","*"], type_detect_rows=1))) == nullness
end

@testset "skiplines_begin" begin
    str1 = """
    hello

    world
    x,y,z
    1,1,1
    """
    @test _csvread(str1, skiplines_begin=3) == (([1], [1], [1]), String["x", "y","z"])
end

using PooledArrays

@testset "pooled array promotion" begin
    # test default behavior
    xs = [randstring(10) for i=1:100]
    col = _csvread(join(xs, "\n"), header_exists=false)[1][1]
    @test isa(col, PooledArray)
    @test eltype(col.refs) == UInt8
    @test xs == col

    # test promotion to a widened type
    xs = [randstring(10) for i=1:300]
    col = _csvread(join(xs, "\n"), header_exists=false)[1][1]
    @test isa(col, PooledArray)
    @test eltype(col.refs) == UInt16
    @test xs == col

    # test promotion to a dense array
    xs = [randstring(10) for i=1:500]
    col = _csvread(join(xs, "\n"), header_exists=false)[1][1]
    @test !isa(col, PooledArray)
    @test isa(col, Array)
    @test xs == col

    # test non-promotion
    xs = [rand(["X", "Y"]) for i=1:500]
    col = _csvread(join(xs, "\n"), header_exists=false)[1][1]
    @test isa(col, PooledArray)
    @test eltype(col.refs) == UInt8
    @test xs == col
end

import TextParse: eatwhitespaces
@testset "custom parser" begin
    const floatparser = Numeric(Float64)
    percentparser = CustomParser(Float64) do str, i, len, opts
        num, ii = tryparsenext(floatparser, str, i, len, opts)
        if isnull(num)
            return num, ii
        else
            # parse away the % char
            ii = eatwhitespaces(str, ii, len)
            c, k = next(str, ii)
            if c != '%'
                return Nullable{Float64}(), ii # failed to parse %
            else
                return num, k # the point after %
            end
        end
    end

    @test tryparsenext(percentparser, "10%")  |> unwrap == (10.0, 4)
    @test tryparsenext(percentparser, "10.32 %") |> unwrap == (10.32, 8)
    @test tryparsenext(percentparser, "2k%") |> failedat ==  2
end
