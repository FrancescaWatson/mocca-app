"""
    MoccaApp

Web application for setting up, configuring, and running CO₂ adsorption
simulations using the [Mocca.jl](https://github.com/sintefmath/Mocca.jl)
simulation toolbox.

Supports loading JSON input files, editing parameter values, exporting
configurations, and running simulations through a responsive web dashboard.

## Quick Start

```julia
using MoccaApp
MoccaApp.start()
```

Then open http://localhost:8000 in a browser.
"""
module MoccaApp

include("InputParameters.jl")
include("Simulation.jl")

using .InputParameters
using .Simulation

export start

"""
    start(; port=8000, host="0.0.0.0")

Start the MoccaApp web server. Open http://localhost:<port> in a browser.
"""
function start(; port::Int=8000, host::String="0.0.0.0")
    include(joinpath(@__DIR__, "..", "app.jl"))
    Base.invokelatest(_start_server; port=port, host=host)
end

end # module
