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
    html(dashboard_html())
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
# HTML Dashboard
# ---------------------------------------------------------------------------

function dashboard_html()
    """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MoccaApp – CO₂ Adsorption Simulation Dashboard</title>
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
<div id="app">
    <!-- Header -->
    <header class="app-header">
        <div class="header-content">
            <h1 class="app-title">☕ MoccaApp</h1>
            <p class="app-subtitle">CO₂ Adsorption Simulation Dashboard — Powered by <a href="https://github.com/sintefmath/Mocca.jl" style="color:#c4b5fd;">Mocca.jl</a></p>
        </div>
    </header>

    <!-- Case Type Navigation -->
    <nav class="case-nav">
        <div class="nav-section">
            <span class="nav-label">Simulation Type:</span>
            <button v-for="c in availableCases" :key="c.key"
                    class="case-btn" :class="{ active: caseType === c.key }"
                    @click="selectCase(c.key)">
                {{ c.label }}
            </button>
        </div>
    </nav>

    <!-- Main Content -->
    <main class="main-content">
        <!-- Case Description -->
        <div class="case-description" v-if="caseInfo">
            <h2>{{ caseInfo.label }}</h2>
            <p>{{ caseInfo.description }}</p>
        </div>

        <div class="content-grid">
            <!-- Left: Parameters Panel -->
            <div class="panel">
                <h3>⚙️ Input Parameters</h3>

                <!-- Actions Bar -->
                <div class="actions-bar" style="margin-top:0; margin-bottom:1rem; border-top:none; padding-top:0;">
                    <label class="file-upload-label">
                        📂 Load JSON
                        <input type="file" accept=".json" class="file-upload-input" @change="loadJsonFile">
                    </label>
                    <button class="btn btn-secondary" @click="exportJson">💾 Export JSON</button>
                    <button class="btn btn-secondary" @click="resetDefaults">🔄 Reset Defaults</button>
                </div>

                <!-- Parameter Categories (Accordion) -->
                <div class="param-list" v-if="categories.length > 0">
                    <div v-for="cat in categories" :key="cat.key" class="category-section">
                        <div class="category-header"
                             :class="{ active: openCategories[cat.key] }"
                             @click="toggleCategory(cat.key)">
                            <span>{{ cat.label }}</span>
                            <span class="category-toggle" :class="{ open: openCategories[cat.key] }">▶</span>
                        </div>
                        <div class="category-fields" v-show="openCategories[cat.key]">
                            <div v-for="field in cat.fields" :key="field.key" class="param-item">
                                <div class="param-header">
                                    <span class="param-label" :title="field.name">
                                        {{ field.name }}
                                        <span v-if="field.symbol" class="param-symbol">({{ field.symbol }})</span>
                                    </span>
                                    <span v-if="field.units && field.units !== 'dimensionless'" class="param-unit">{{ field.units }}</span>
                                </div>
                                <!-- Array values -->
                                <input v-if="Array.isArray(field.value)"
                                       class="param-input is-array"
                                       :value="JSON.stringify(field.value)"
                                       @change="onArrayParamChange(cat.key, field.key, \$event)">
                                <!-- String values -->
                                <template v-else-if="typeof field.value === 'string'">
                                    <!-- String array (for stage_types) -->
                                    <input class="param-input"
                                           :value="field.value"
                                           @change="onParamChange(cat.key, field.key, \$event.target.value)">
                                </template>
                                <!-- Object values (timestep selectors, etc.) -->
                                <template v-else-if="typeof field.value === 'object' && field.value !== null && !Array.isArray(field.value)">
                                    <input class="param-input is-array"
                                           :value="JSON.stringify(field.value)"
                                           @change="onObjectParamChange(cat.key, field.key, \$event)">
                                </template>
                                <!-- Numeric values -->
                                <input v-else
                                       type="number"
                                       class="param-input"
                                       :value="field.value"
                                       :step="getStep(field.value)"
                                       @change="onParamChange(cat.key, field.key, parseFloat(\$event.target.value))">
                            </div>
                        </div>
                    </div>
                </div>
                <div v-else class="no-data">Loading parameters...</div>

                <!-- Validation Errors -->
                <div v-if="validationErrors.length > 0" class="validation-errors">
                    <h4>⚠️ Validation Errors</h4>
                    <ul>
                        <li v-for="err in validationErrors" :key="err.field">
                            <strong>{{ err.field }}:</strong> {{ err.message }}
                        </li>
                    </ul>
                </div>
            </div>

            <!-- Right: Simulation & Results Panel -->
            <div class="panel">
                <h3>🚀 Simulation</h3>

                <!-- Run Simulation -->
                <div class="actions-bar" style="margin-top:0; border-top:none; padding-top:0;">
                    <button class="btn btn-success" @click="runSimulation" :disabled="simStatus === 'RUNNING'">
                        ▶ Run Simulation
                    </button>
                    <button class="btn btn-primary" @click="validateParams">
                        ✓ Validate
                    </button>
                </div>

                <!-- Status -->
                <div style="margin-top: 1rem;">
                    <div v-if="simStatus === 'IDLE'" class="status-idle">
                        Ready to simulate. Configure parameters and click "Run Simulation".
                    </div>
                    <div v-if="simStatus === 'RUNNING'" class="status-running">
                        <span class="spinner"></span> Running simulation... This may take a moment.
                    </div>
                    <div v-if="simStatus === 'COMPLETED'" class="status-completed">
                        ✅ {{ simMessage }}
                    </div>
                    <div v-if="simStatus === 'FAILED'" class="status-failed">
                        ❌ {{ simMessage }}
                    </div>
                </div>

                <!-- Results Summary -->
                <div v-if="simOutput && simStatus === 'COMPLETED'" class="result-summary">
                    <h4>Results Summary</h4>
                    <table class="summary-table">
                        <tr v-if="simOutput.num_states">
                            <td class="summary-label">Total timesteps</td>
                            <td class="summary-value">{{ simOutput.num_states }}</td>
                        </tr>
                        <tr v-if="simOutput.total_time">
                            <td class="summary-label">Total simulation time</td>
                            <td class="summary-value">{{ formatNumber(simOutput.total_time) }} s</td>
                        </tr>
                    </table>
                </div>

                <!-- JSON Preview -->
                <div class="json-preview" style="margin-top: 1.5rem;">
                    <h3 style="border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; margin-bottom: 0.75rem;">
                        📋 JSON Preview
                    </h3>
                    <pre>{{ jsonPreview }}</pre>
                </div>
            </div>
        </div>
    </main>

    <!-- Footer -->
    <footer class="app-footer">
        <p>
            <strong>MoccaApp</strong> — A web interface for
            <a href="https://github.com/sintefmath/Mocca.jl" target="_blank">Mocca.jl</a>
            · Built with <a href="https://genieframework.com/" target="_blank">Genie.jl</a>
            and <a href="https://vuejs.org/" target="_blank">Vue.js</a>
        </p>
    </footer>
</div>

<!-- Vue.js 3 from CDN -->
<script src="/js/vue.global.prod.js"></script>
<script>
const { createApp, ref, reactive, computed, onMounted, watch, nextTick } = Vue;

createApp({
    setup() {
        const caseType = ref('cyclic');
        const caseInfo = ref(null);
        const params = ref({});
        const categories = ref([]);
        const openCategories = reactive({});
        const validationErrors = ref([]);
        const simStatus = ref('IDLE');
        const simMessage = ref('');
        const simOutput = ref(null);

        const availableCases = [
            { key: 'cyclic', label: 'Cyclic VSA' },
            { key: 'dcb', label: 'Direct Column Breakthrough' },
        ];

        const jsonPreview = computed(() => {
            try {
                return JSON.stringify(params.value, null, 2);
            } catch {
                return '{}';
            }
        });

        function getStep(value) {
            if (!value || typeof value !== 'number') return 1;
            const abs = Math.abs(value);
            if (abs === 0) return 1;
            if (abs < 0.001) return 0.0001;
            if (abs < 0.01) return 0.001;
            if (abs < 0.1) return 0.01;
            if (abs < 1) return 0.1;
            if (abs < 100) return 1;
            if (abs < 10000) return 10;
            return 100;
        }

        function formatNumber(v) {
            if (typeof v !== 'number') return v;
            return v.toLocaleString(undefined, { maximumFractionDigits: 4 });
        }

        async function loadCaseDefaults(caseName) {
            try {
                const resp = await fetch('/api/defaults/' + caseName);
                if (!resp.ok) throw new Error(await resp.text());
                const data = await resp.json();
                caseInfo.value = { label: data.label, description: data.description };
                params.value = data.params;
                categories.value = data.categories;
                // Open first category by default
                for (const cat of data.categories) {
                    if (!(cat.key in openCategories)) {
                        openCategories[cat.key] = false;
                    }
                }
                if (data.categories.length > 0) {
                    openCategories[data.categories[0].key] = true;
                }
                validationErrors.value = [];
                simStatus.value = 'IDLE';
                simMessage.value = '';
                simOutput.value = null;
            } catch (e) {
                console.error('Failed to load defaults:', e);
            }
        }

        function selectCase(caseName) {
            caseType.value = caseName;
            loadCaseDefaults(caseName);
        }

        function toggleCategory(catKey) {
            openCategories[catKey] = !openCategories[catKey];
        }

        function isDetailed() {
            const p = params.value;
            return p && p.columnProps && typeof p.columnProps.L === 'object' && p.columnProps.L !== null && 'value' in p.columnProps.L;
        }

        function onParamChange(catKey, fieldKey, newValue) {
            if (isDetailed()) {
                if (params.value[catKey] && params.value[catKey][fieldKey] && typeof params.value[catKey][fieldKey] === 'object' && 'value' in params.value[catKey][fieldKey]) {
                    params.value[catKey][fieldKey]['value'] = newValue;
                }
            } else {
                if (params.value[catKey]) {
                    params.value[catKey][fieldKey] = newValue;
                }
            }
            // Update the category field value too
            const cat = categories.value.find(c => c.key === catKey);
            if (cat) {
                const field = cat.fields.find(f => f.key === fieldKey);
                if (field) field.value = newValue;
            }
        }

        function onArrayParamChange(catKey, fieldKey, event) {
            try {
                const parsed = JSON.parse(event.target.value);
                if (Array.isArray(parsed)) {
                    onParamChange(catKey, fieldKey, parsed);
                }
            } catch {
                console.warn('Invalid array input');
            }
        }

        function onObjectParamChange(catKey, fieldKey, event) {
            try {
                const parsed = JSON.parse(event.target.value);
                if (typeof parsed === 'object' && parsed !== null) {
                    onParamChange(catKey, fieldKey, parsed);
                }
            } catch {
                console.warn('Invalid object input');
            }
        }

        function resetDefaults() {
            loadCaseDefaults(caseType.value);
        }

        function loadJsonFile(event) {
            const file = event.target.files[0];
            if (!file) return;
            const reader = new FileReader();
            reader.onload = (e) => {
                try {
                    const data = JSON.parse(e.target.result);
                    params.value = data;
                    categories.value = [];
                    // Re-fetch categories from server
                    fetch('/api/defaults/' + caseType.value)
                        .then(r => r.json())
                        .then(d => {
                            // Use the loaded params but re-derive categories
                            const cats = buildCategories(data);
                            categories.value = cats;
                        })
                        .catch(() => {
                            // Fallback: build categories client-side
                            categories.value = buildCategories(data);
                        });
                } catch (err) {
                    alert('Failed to parse JSON file: ' + err.message);
                }
            };
            reader.readAsText(file);
            event.target.value = '';
        }

        function buildCategories(data) {
            const catOrder = [
                'physicalConstants', 'dslPars', 'adsorbentProps', 'columnProps',
                'feedProps', 'boundaryConditions', 'initialConditions',
                'processSpecification', 'simulation', 'solver'
            ];
            const catLabels = {
                physicalConstants: 'Physical Constants',
                dslPars: 'Dual-Site Langmuir Parameters',
                adsorbentProps: 'Adsorbent Properties',
                columnProps: 'Column Properties',
                feedProps: 'Feed Gas Properties',
                boundaryConditions: 'Boundary Conditions',
                initialConditions: 'Initial Conditions',
                processSpecification: 'Process Specification',
                simulation: 'Simulation Settings',
                solver: 'Solver Settings',
            };
            const isDetailed = data.columnProps && typeof data.columnProps.L === 'object'
                             && data.columnProps.L !== null && 'value' in data.columnProps.L;
            const cats = [];
            for (const key of catOrder) {
                if (!data[key] || typeof data[key] !== 'object') continue;
                const fields = [];
                for (const [fk, fv] of Object.entries(data[key])) {
                    if (isDetailed && typeof fv === 'object' && fv !== null && 'value' in fv) {
                        const desc = fv.description || {};
                        fields.push({
                            key: fk,
                            value: fv.value,
                            name: desc.name || fk,
                            symbol: desc.symbol || '',
                            units: desc.units || '',
                        });
                    } else {
                        fields.push({ key: fk, value: fv, name: fk, symbol: '', units: '' });
                    }
                }
                cats.push({ key: key, label: catLabels[key] || key, fields: fields });
            }
            return cats;
        }

        function exportJson() {
            const json = JSON.stringify(params.value, null, 2);
            const blob = new Blob([json], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = caseType.value + '_input.json';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        }

        async function validateParams() {
            try {
                const resp = await fetch('/api/validate', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ params: params.value }),
                });
                const data = await resp.json();
                validationErrors.value = data.errors || [];
                if (data.valid) {
                    simMessage.value = 'Parameters are valid.';
                }
            } catch (e) {
                console.error('Validation failed:', e);
            }
        }

        async function runSimulation() {
            simStatus.value = 'RUNNING';
            simMessage.value = '';
            simOutput.value = null;
            validationErrors.value = [];
            try {
                const resp = await fetch('/api/simulate', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ params: params.value }),
                });
                const data = await resp.json();
                simStatus.value = data.status;
                simMessage.value = data.message;
                simOutput.value = data.output || null;
            } catch (e) {
                simStatus.value = 'FAILED';
                simMessage.value = 'Request failed: ' + e.message;
            }
        }

        onMounted(() => {
            loadCaseDefaults(caseType.value);
        });

        return {
            caseType, caseInfo, params, categories, openCategories,
            validationErrors, simStatus, simMessage, simOutput,
            availableCases, jsonPreview,
            selectCase, toggleCategory, getStep, formatNumber,
            onParamChange, onArrayParamChange, onObjectParamChange,
            resetDefaults, loadJsonFile, exportJson,
            validateParams, runSimulation,
            JSON
        };
    }
}).mount('#app');
</script>
</body>
</html>
"""
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
