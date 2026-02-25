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

function __init__()
    HAS_MOCCA[] = try
        @eval using Mocca
        true
    catch
        false
    end
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
        try
            @eval Main using Mocca
            HAS_MOCCA[] = true
        catch e
            result.status = FAILED
            result.message = "Mocca.jl is not installed. Please install it with: using Pkg; Pkg.add(\"Mocca\")"
            return result
        end
    end

    try
        result.status = RUNNING

        # Use Mocca's parse_input to create constants and info from dict
        mocca = Main.Mocca
        (constants, info) = mocca.parse_input(params)

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
