"""
    InputParameters

Parameter management for Mocca.jl adsorption simulations.
Handles loading, validating, and exporting JSON input files
in both simple and detailed formats.
"""
module InputParameters

using JSON

export load_default_params, load_params_from_file, load_params_from_dict
export validate_params, params_to_dict, get_param_categories
export AVAILABLE_CASES, CASE_LABELS, CASE_DESCRIPTIONS

const AVAILABLE_CASES = ["cyclic", "dcb"]

const CASE_LABELS = Dict(
    "cyclic" => "Cyclic Vacuum Swing Adsorption",
    "dcb"    => "Direct Column Breakthrough",
)

const CASE_DESCRIPTIONS = Dict(
    "cyclic" => "A 4-stage vacuum swing adsorption process for CO₂ capture from a two-component flue gas (CO₂/N₂) using Zeolite 13X, as described by Haghpanah et al. (2013).",
    "dcb"    => "A direct column breakthrough simulation modelling adsorption of CO₂ from a flue gas onto Zeolite 13X.",
)

const MODELS_DIR = joinpath(@__DIR__, "..", "models", "json")

"""Map case names to their default JSON files."""
const CASE_FILES = Dict(
    "cyclic" => "haghpanah_cyclic_input.json",
    "dcb"    => "haghpanah_DCB_input.json",
)

"""Human-readable category labels for the JSON sections."""
const CATEGORY_LABELS = Dict(
    "physicalConstants"    => "Physical Constants",
    "dslPars"              => "Dual-Site Langmuir Parameters",
    "adsorbentProps"       => "Adsorbent Properties",
    "columnProps"          => "Column Properties",
    "feedProps"            => "Feed Gas Properties",
    "boundaryConditions"   => "Boundary Conditions",
    "initialConditions"    => "Initial Conditions",
    "processSpecification" => "Process Specification",
    "simulation"           => "Simulation Settings",
    "solver"               => "Solver Settings",
)

"""Ordered list of parameter categories for display."""
const CATEGORY_ORDER = [
    "physicalConstants",
    "dslPars",
    "adsorbentProps",
    "columnProps",
    "feedProps",
    "boundaryConditions",
    "initialConditions",
    "processSpecification",
    "simulation",
    "solver",
]

"""
    is_detailed_format(d::Dict) -> Bool

Check whether the JSON dictionary uses the detailed format (with description/value).
"""
function is_detailed_format(d::AbstractDict)
    if !haskey(d, "columnProps")
        return false
    end
    cp = d["columnProps"]
    if haskey(cp, "L") && isa(cp["L"], AbstractDict) && haskey(cp["L"], "value")
        return true
    end
    return false
end

"""
    load_default_params(case_name::String) -> Dict

Load default parameters for a named case from the bundled JSON files.
Returns the parsed dictionary in detailed format.
"""
function load_default_params(case_name::String)
    case_name = lowercase(strip(case_name))
    if !haskey(CASE_FILES, case_name)
        error("Unknown case: $case_name. Available: $(join(AVAILABLE_CASES, ", "))")
    end
    filepath = joinpath(MODELS_DIR, CASE_FILES[case_name])
    return load_params_from_file(filepath)
end

"""
    load_params_from_file(filepath::String) -> Dict

Load parameters from a JSON file path. Supports both simple and detailed formats.
"""
function load_params_from_file(filepath::String)
    d = JSON.parsefile(filepath)
    return d
end

"""
    load_params_from_dict(d::Dict) -> Dict

Accept a dictionary (e.g. from JSON payload) and return it.
"""
function load_params_from_dict(d::AbstractDict)
    return d
end

"""
    extract_value(entry)

Extract the raw value from a parameter entry.
Works for both detailed format (Dict with "value" key) and simple format (raw value).
"""
function extract_value(entry)
    if isa(entry, AbstractDict) && haskey(entry, "value")
        return entry["value"]
    end
    return entry
end

"""
    get_param_categories(d::Dict) -> Vector{Dict}

Return an ordered list of parameter categories with their fields for UI rendering.
Each category has: key, label, and fields (list of field dicts).
"""
function get_param_categories(d::AbstractDict)
    detailed = is_detailed_format(d)
    categories = []
    for cat_key in CATEGORY_ORDER
        if !haskey(d, cat_key)
            continue
        end
        cat_data = d[cat_key]
        if !isa(cat_data, AbstractDict)
            continue
        end
        fields = []
        for (field_key, field_val) in cat_data
            if detailed && isa(field_val, AbstractDict) && haskey(field_val, "value")
                desc = get(field_val, "description", Dict())
                push!(fields, Dict(
                    "key"     => field_key,
                    "value"   => field_val["value"],
                    "name"    => get(desc, "name", field_key),
                    "symbol"  => get(desc, "symbol", ""),
                    "units"   => get(desc, "units", ""),
                ))
            else
                push!(fields, Dict(
                    "key"   => field_key,
                    "value" => field_val,
                    "name"  => field_key,
                    "symbol" => "",
                    "units" => "",
                ))
            end
        end
        push!(categories, Dict(
            "key"    => cat_key,
            "label"  => get(CATEGORY_LABELS, cat_key, cat_key),
            "fields" => fields,
        ))
    end
    return categories
end

"""
    update_params(d::Dict, updates::Dict) -> Dict

Apply a flat dictionary of updates to the parameter dictionary.
`updates` maps "category.field" => new_value.
"""
function update_params(d::AbstractDict, updates::AbstractDict)
    detailed = is_detailed_format(d)
    result = deepcopy(d)
    for (path, new_val) in updates
        parts = split(path, ".")
        if length(parts) == 2
            cat, field = String(parts[1]), String(parts[2])
            if haskey(result, cat) && isa(result[cat], AbstractDict)
                if haskey(result[cat], field)
                    if detailed && isa(result[cat][field], AbstractDict) && haskey(result[cat][field], "value")
                        result[cat][field]["value"] = new_val
                    else
                        result[cat][field] = new_val
                    end
                end
            end
        end
    end
    return result
end

"""
    validate_params(d::Dict) -> Vector{Dict}

Validate the parameter dictionary and return a list of error dictionaries.
Each error has :field and :message keys.
"""
function validate_params(d::AbstractDict)
    errors = Dict{String,String}[]

    # Check required top-level sections
    required = ["physicalConstants", "dslPars", "adsorbentProps", "columnProps",
                 "feedProps", "boundaryConditions", "initialConditions"]
    for sec in required
        if !haskey(d, sec)
            push!(errors, Dict("field" => sec, "message" => "Missing required section: $sec"))
        end
    end

    if !isempty(errors)
        return errors
    end

    # Validate specific numeric constraints
    detailed = is_detailed_format(d)
    function getval(cat, field)
        if !haskey(d, cat) || !haskey(d[cat], field)
            return nothing
        end
        entry = d[cat][field]
        return extract_value(entry)
    end

    # Column length must be positive
    L = getval("columnProps", "L")
    if !isnothing(L) && isa(L, Number) && L <= 0
        push!(errors, Dict("field" => "columnProps.L", "message" => "Column length must be positive"))
    end

    # Bed porosity must be between 0 and 1
    phi = getval("columnProps", "Φ")
    if !isnothing(phi) && isa(phi, Number) && (phi <= 0 || phi >= 1)
        push!(errors, Dict("field" => "columnProps.Φ", "message" => "Bed porosity must be between 0 and 1"))
    end

    # Particle porosity must be between 0 and 1
    ep = getval("adsorbentProps", "ϵ_p")
    if !isnothing(ep) && isa(ep, Number) && (ep <= 0 || ep >= 1)
        push!(errors, Dict("field" => "adsorbentProps.ϵ_p", "message" => "Particle porosity must be between 0 and 1"))
    end

    # Number of cells must be positive
    ncells = getval("simulation", "ncells")
    if !isnothing(ncells) && isa(ncells, Number) && ncells < 1
        push!(errors, Dict("field" => "simulation.ncells", "message" => "Number of cells must be at least 1"))
    end

    # Feed temperature must be positive
    T_feed = getval("feedProps", "T_feed")
    if !isnothing(T_feed) && isa(T_feed, Number) && T_feed <= 0
        push!(errors, Dict("field" => "feedProps.T_feed", "message" => "Feed temperature must be positive"))
    end

    return errors
end

"""
    params_to_dict(d::Dict) -> Dict

Convert parameters to a clean dictionary suitable for JSON export.
Strips any internal metadata, keeping values in their original format.
"""
function params_to_dict(d::AbstractDict)
    return deepcopy(d)
end

end # module
