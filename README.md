# MoccaApp

Web application for setting up, configuring, and running CO₂ adsorption
simulations using [Mocca.jl](https://github.com/sintefmath/Mocca.jl).

## Features

- **Load JSON input files** – Load standard Mocca.jl JSON input files (both simple and detailed formats)
- **Edit parameters** – Modify all simulation parameters through an intuitive categorized interface
- **Export JSON** – Download the modified parameter configuration as a JSON file
- **Run simulations** – Execute Mocca.jl simulations directly from the browser
- **Default configurations** – Ships with Haghpanah cyclic VSA and DCB simulation defaults
- **Responsive design** – Works on desktop and tablet screens
- **API-first** – JSON REST API for programmatic access

## Getting Started

### Prerequisites

- [Julia](https://julialang.org/) ≥ 1.10

### Installation

Clone this repository and install dependencies:

```bash
git clone https://github.com/FrancescaWatson/mocca-app.git
cd mocca-app
```

Then, in the Julia REPL:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

### Running the Application

**Option 1: Using the module**

```julia
using Pkg
Pkg.activate(".")

using MoccaApp
MoccaApp.start()
```

**Option 2: Running app.jl directly**

```julia
using Pkg
Pkg.activate(".")

include("app.jl")
```

Then open [http://localhost:8000](http://localhost:8000) in your browser.

To use a different port:

```julia
MoccaApp.start(port=9000)
```

### Running Simulations

To actually run CO₂ adsorption simulations (not just configure them), install Mocca.jl:

```julia
using Pkg
Pkg.add("Mocca")
```

When Mocca.jl is installed, the simulation backend is automatically activated
and you can run simulations directly from the web dashboard.

## Supported Simulation Types

- **Cyclic Vacuum Swing Adsorption (VSA)** – A 4-stage process (pressurisation, adsorption, blowdown, evacuation) for CO₂ capture from flue gas using Zeolite 13X, as described by Haghpanah et al. (2013).
- **Direct Column Breakthrough (DCB)** – A direct column breakthrough simulation modelling adsorption of CO₂ from flue gas onto Zeolite 13X.

## Architecture

Built with [Genie.jl](https://genieframework.com/) and a [Vue.js](https://vuejs.org/) frontend:

```
mocca-app/
├── src/
│   ├── MoccaApp.jl           # Main module
│   ├── InputParameters.jl    # Parameter loading, validation, export
│   └── Simulation.jl         # Mocca.jl simulation interface
├── app.jl                    # Web server and routes
├── public/css/style.css      # Dashboard styles
├── models/json/              # Default JSON input files
│   ├── haghpanah_cyclic_input.json
│   └── haghpanah_DCB_input.json
├── test/runtests.jl          # Tests
├── Project.toml              # Julia package dependencies
└── README.md                 # This file
```

## API Endpoints

| Method | Endpoint                  | Description                         |
|--------|---------------------------|-------------------------------------|
| GET    | `/`                       | Dashboard UI                        |
| GET    | `/api/defaults/:case`     | Default parameters for a case type  |
| POST   | `/api/validate`           | Validate parameter values           |
| POST   | `/api/simulate`           | Run a simulation                    |
| POST   | `/api/export`             | Export parameters as JSON           |

## Running Tests

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

Or directly:

```bash
julia --project=. test/runtests.jl
```

## License

MIT
