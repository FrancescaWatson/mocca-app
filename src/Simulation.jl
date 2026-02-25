"""
    Simulation

Interface for running Mocca.jl adsorption simulations via the web application.
This module provides the simulation API that bridges the web UI with Mocca.jl.

When Mocca.jl is not installed, simulation endpoints return informative error messages.
"""
module Simulation

using ..InputParameters
using JSON

export SimulationStatus, IDLE, RUNNING, COMPLETED, FAILED
export SimulationResult, run_simulation

@enum SimulationStatus IDLE RUNNING COMPLETED FAILED

"""Container for simulation results."""
mutable struct SimulationResult
    status::SimulationStatus
    message::String
    output_data::Dict{String, Any}
    SimulationResult() = new(IDLE, "", Dict{String, Any}())
end

# Check if Mocca is available
const HAS_MOCCA = Ref(false)
const MOCCA_MOD = Ref{Module}()

function _load_mocca!()
    try
        @eval using Mocca
        MOCCA_MOD[] = @eval Mocca
        HAS_MOCCA[] = true
        return true
    catch
        return false
    end
end

function __init__()
    _load_mocca!()
end

"""
    _to_plain_dict(d) -> Dict{String,Any}

Recursively convert an AbstractDict (e.g. JSON.Object) to Dict{String,Any}.
"""
function _to_plain_dict(d::AbstractDict)
    result = Dict{String,Any}()
    for (k, v) in d
        result[string(k)] = _to_plain_value(v)
    end
    return result
end

function _to_plain_value(v::AbstractDict)
    return _to_plain_dict(v)
end

function _to_plain_value(v::AbstractVector)
    return Any[_to_plain_value(x) for x in v]
end

function _to_plain_value(v)
    return v
end

"""
    run_simulation(params::Dict) -> SimulationResult

Run a Mocca simulation with the given parameter dictionary.
Returns a SimulationResult with status, message, and output data.
"""
function run_simulation(params::AbstractDict)
    result = SimulationResult()

    # Validate parameters first
    errors = validate_params(params)
    if !isempty(errors)
        result.status = FAILED
        result.message = join(["$(e["field"]): $(e["message"])" for e in errors], "; ")
        return result
    end

    if !HAS_MOCCA[]
        if !_load_mocca!()
            result.status = FAILED
            result.message = "Mocca.jl is not installed. Please install it with: using Pkg; Pkg.add(\"Mocca\")"
            return result
        end
    end

    try
        result.status = RUNNING

        mocca = MOCCA_MOD[]
        # Convert to Dict{String,Any} to satisfy Mocca's type requirements
        plain = _to_plain_dict(params)
        (constants, info) = mocca.parse_input(plain)

        # Setup and run simulation
        case, ts_config, info_level = mocca.setup_mocca_case(constants, info)
        states, timesteps = mocca.simulate_process(case;
            timestep_selector_cfg = ts_config,
            output_substates = true,
            info_level = info_level
        )

        result.status = COMPLETED
        result.message = "Simulation completed successfully. $(length(states)) timesteps computed."
        result.output_data["num_states"] = length(states)
        result.output_data["total_time"] = sum(timesteps)
        result.output_data["timesteps"] = Float64.(timesteps)

    catch e
        result.status = FAILED
        result.message = "Simulation failed: $(sprint(showerror, e))"
    end

    return result
end

end # module
