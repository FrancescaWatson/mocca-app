"""
MoccaApp web application entry point.

Starts a Genie.jl web server with a reactive dashboard for configuring
and running CO₂ adsorption simulations via Mocca.jl.

    julia app.jl              # start on default port 8000
    julia app.jl --port=9000  # start on custom port
"""

using Genie, Genie.Renderer.Html, Genie.Requests
using JSON
using Dates

# Load MoccaApp modules
if !isdefined(@__MODULE__, :InputParameters)
    include(joinpath(@__DIR__, "src", "InputParameters.jl"))
end
if !isdefined(@__MODULE__, :Simulation)
    include(joinpath(@__DIR__, "src", "Simulation.jl"))
end
using .InputParameters
using .Simulation

# ---------------------------------------------------------------------------
# Serve static files
# ---------------------------------------------------------------------------
const PUBLIC_DIR = joinpath(@__DIR__, "public")

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

route("/") do
    Genie.Renderer.respond(
        read(joinpath(PUBLIC_DIR, "index.html"), String),
        :html
    )
end

route("/css/style.css") do
    Genie.Renderer.respond(
        read(joinpath(PUBLIC_DIR, "css", "style.css"), String),
        :css
    )
end

route("/js/vue.global.prod.js") do
    Genie.Renderer.respond(
        read(joinpath(PUBLIC_DIR, "js", "vue.global.prod.js"), String),
        :javascript
    )
end

route("/api/defaults/:case_name") do
    cn = lowercase(strip(payload(:case_name)))
    if !(cn in AVAILABLE_CASES)
        return Genie.Renderer.respond("Invalid case name. Available: $(join(AVAILABLE_CASES, ", "))", :text, status=400)
    end
    params = load_default_params(cn)
    categories = get_param_categories(params)
    return Genie.Renderer.Json.json(Dict(
        :case_name   => cn,
        :label       => CASE_LABELS[cn],
        :description => CASE_DESCRIPTIONS[cn],
        :params      => params,
        :categories  => categories,
    ))
end

route("/api/validate", method=POST) do
    data = jsonpayload()
    isnothing(data) && return Genie.Renderer.respond("Invalid JSON", :text, status=400)
    params = get(data, "params", data)
    errors = validate_params(params)
    return Genie.Renderer.Json.json(Dict(
        :valid  => isempty(errors),
        :errors => errors,
    ))
end

route("/api/simulate", method=POST) do
    data = jsonpayload()
    isnothing(data) && return Genie.Renderer.respond("Invalid JSON", :text, status=400)
    params = get(data, "params", data)
    result = run_simulation(params)
    return Genie.Renderer.Json.json(Dict(
        :status  => string(result.status),
        :message => result.message,
        :output  => result.output_data,
    ))
end

route("/api/export", method=POST) do
    data = jsonpayload()
    isnothing(data) && return Genie.Renderer.respond("Invalid JSON", :text, status=400)
    params = get(data, "params", data)
    json_str = JSON.json(params, 2)
    return Genie.Renderer.respond(json_str, :json)
end

# ---------------------------------------------------------------------------
# Server start
# ---------------------------------------------------------------------------

function _start_server(; port::Int=8000, host::String="0.0.0.0")
    Genie.config.run_as_server = true
    up(port, host)
end

# Allow running directly: julia app.jl
if abspath(PROGRAM_FILE) == @__FILE__
    _start_server()
end
