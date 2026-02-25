using Test

# Load the InputParameters module directly for testing
include(joinpath(@__DIR__, "..", "src", "InputParameters.jl"))
using .InputParameters

@testset "MoccaApp" begin

    @testset "Available cases" begin
        @test "cyclic" in AVAILABLE_CASES
        @test "dcb" in AVAILABLE_CASES
    end

    @testset "Case labels and descriptions" begin
        for c in AVAILABLE_CASES
            @test haskey(CASE_LABELS, c)
            @test haskey(CASE_DESCRIPTIONS, c)
            @test !isempty(CASE_LABELS[c])
            @test !isempty(CASE_DESCRIPTIONS[c])
        end
    end

    @testset "Load default parameters" begin
        @testset "Cyclic case" begin
            d = load_default_params("cyclic")
            @test haskey(d, "physicalConstants")
            @test haskey(d, "dslPars")
            @test haskey(d, "adsorbentProps")
            @test haskey(d, "columnProps")
            @test haskey(d, "feedProps")
            @test haskey(d, "boundaryConditions")
            @test haskey(d, "initialConditions")
            @test haskey(d, "processSpecification")
            @test haskey(d, "simulation")
            @test haskey(d, "solver")
        end

        @testset "DCB case" begin
            d = load_default_params("dcb")
            @test haskey(d, "physicalConstants")
            @test haskey(d, "columnProps")
        end

        @testset "Invalid case" begin
            @test_throws ErrorException load_default_params("nonexistent")
        end
    end

    @testset "Detect detailed format" begin
        d = load_default_params("cyclic")
        @test InputParameters.is_detailed_format(d) == true

        # Simple format test
        simple = Dict(
            "columnProps" => Dict("L" => 1.0),
            "physicalConstants" => Dict("R" => 8.314),
        )
        @test InputParameters.is_detailed_format(simple) == false
    end

    @testset "Get parameter categories" begin
        d = load_default_params("cyclic")
        cats = get_param_categories(d)
        @test length(cats) > 0
        @test cats[1]["key"] == "physicalConstants"
        @test haskey(cats[1], "label")
        @test haskey(cats[1], "fields")
        @test length(cats[1]["fields"]) > 0

        # Each field should have key, value, name
        f = cats[1]["fields"][1]
        @test haskey(f, "key")
        @test haskey(f, "value")
        @test haskey(f, "name")
    end

    @testset "Validate parameters" begin
        @testset "Valid parameters" begin
            d = load_default_params("cyclic")
            errors = validate_params(d)
            @test isempty(errors)
        end

        @testset "Missing section" begin
            d = Dict{String,Any}()
            errors = validate_params(d)
            @test !isempty(errors)
            @test any(e -> occursin("Missing required section", e["message"]), errors)
        end

        @testset "Invalid column length" begin
            d = load_default_params("cyclic")
            d["columnProps"]["L"]["value"] = -1.0
            errors = validate_params(d)
            @test any(e -> e["field"] == "columnProps.L", errors)
        end

        @testset "Invalid porosity" begin
            d = load_default_params("cyclic")
            d["columnProps"]["Φ"]["value"] = 1.5
            errors = validate_params(d)
            @test any(e -> e["field"] == "columnProps.Φ", errors)
        end
    end

    @testset "Update parameters" begin
        d = load_default_params("cyclic")
        original_L = d["columnProps"]["L"]["value"]
        updated = InputParameters.update_params(d, Dict("columnProps.L" => 2.0))
        @test updated["columnProps"]["L"]["value"] == 2.0
        # Original should be unchanged
        @test d["columnProps"]["L"]["value"] == original_L
    end

    @testset "Extract value" begin
        @test InputParameters.extract_value(Dict("value" => 42)) == 42
        @test InputParameters.extract_value(3.14) == 3.14
        @test InputParameters.extract_value("hello") == "hello"
    end

    @testset "Params to dict" begin
        d = load_default_params("cyclic")
        exported = params_to_dict(d)
        @test exported == d
        # Should be a deep copy
        exported["columnProps"]["L"]["value"] = 999.0
        @test d["columnProps"]["L"]["value"] != 999.0
    end

end
