# Nextflow Workflow Manager Cheatsheet for AI Agents (2024-2025)

## Table of Contents
1. [Installation via Pixi](#1-installation-via-pixi)
2. [Channel Management](#2-channel-management)
3. [Project Structure](#3-project-structure)
4. [Resume & Checkpoints](#4-resume--checkpoints)
5. [Testing Strategies](#5-testing-strategies)
6. [Quick Reference Commands](#6-quick-reference-commands)

---

## 1. Installation via Pixi

### Quick Install
```bash
# Install Pixi package manager
curl -fsSL https://pixi.sh/install.sh | bash

# Configure for bioinformatics
pixi config append default-channels conda-forge --global
pixi config append default-channels bioconda --global

# Global Nextflow installation
pixi global install -c bioconda nextflow
```

### Basic pixi.toml Configuration
```toml
[project]
name = "nextflow-bioinformatics"
version = "0.1.0"
authors = ["Your Name <email@example.com>"]
channels = ["conda-forge", "bioconda"]
platforms = ["linux-64", "osx-64", "osx-arm64"]

[dependencies]
nextflow = "25.4.*"
openjdk = "17.*"
python = "3.11.*"
samtools = "1.20.*"
bcftools = "1.20.*"
fastqc = "0.12.*"
multiqc = "1.21.*"

[tasks]
run-pipeline = "nextflow run main.nf"
run-test = "nextflow run main.nf -profile test"
run-docker = "nextflow run main.nf -profile docker"
clean = "nextflow clean -f"
```

### Multi-Environment Configuration
```toml
[feature.dev.dependencies]
pytest = "8.2.*"
black = "24.4.*"
jupyter = "1.0.*"

[feature.prod.dependencies]
# Minimal production deps
nextflow = "25.4.*"
openjdk = "17.*"

[feature.genomics.dependencies]
bwa = "0.7.*"
gatk4 = "4.5.*"
picard = "3.1.*"

[environments]
default = ["dev"]
production = ["prod"]
genomics = ["genomics"]

[tasks]
dev-setup = "pre-commit install"
prod-deploy = { cmd = "nextflow run main.nf -profile production", env = "production" }
```

---

## 2. Channel Management

### Channel Types (2024-2025)

#### 1. Queue Channels
```groovy
// Standard FIFO channels
ch_files = channel.fromPath('data/*.fastq')
ch_numbers = channel.of(1, 2, 3, 4, 5)
ch_list = channel.fromList(['alpha', 'beta', 'gamma'])
```

#### 2. Value Channels
```groovy
// Single value, consumed unlimited times
ch_reference = channel.value('/path/to/reference.fa')
ch_config = channel.value(params.config_file)
```

#### 3. Topic Channels (NEW in 24.04/25.04)
```groovy
// Pub/sub messaging pattern
process quality_check {
  output:
  val "${fastq.baseName}_qc_passed", topic: 'qc_results'
  
  script:
  """
  fastqc $fastq
  """
}

workflow {
  // Collect from topic
  channel.topic('qc_results')
    .collect()
    .view { "All QC results: $it" }
}
```

### Data Lineage Channel Factory (NEW in 25.04)
```groovy
// Access files from previous runs
channel.fromLineage(
  workflowRun: 'lid://0d1d1622ced3e4edc690bec768919b45',
  label: ['processed_samples', 'quality_reports']
)

// Enable in config
lineage {
  enabled = true
  store = '.lineage'
}
```

### Advanced Channel Operations
```groovy
// Complex joining with metadata
samples_ch = channel.fromPath('samples/*.fastq')
  .map { file -> [file.baseName, file] }

metadata_ch = channel.fromPath('metadata.csv')
  .splitCsv(header: true)
  .map { row -> [row.sample_id, row] }

combined_ch = samples_ch
  .join(metadata_ch, by: 0)
  .map { sample_id, fastq, metadata -> 
    [sample_id, fastq, metadata.condition, metadata.batch]
  }

// Conditional branching
channel.fromPath('results/*.vcf')
  .filter { file -> file.size() > 1000 }
  .branch {
    high_quality: it.text.contains('PASS')
    low_quality: true
  }
```

### Topic Channel Patterns
```groovy
process fastqc {
  output:
  path 'fastqc_report.html'
  path 'versions.txt', topic: 'software_versions'
  tuple val("${fastq.baseName}"), val('fastqc'), path('stats.txt'), topic: 'qc_stats'
  
  script:
  """
  fastqc $fastq
  echo "FastQC: $(fastqc --version)" > versions.txt
  """
}

workflow {
  // Collect software versions
  channel.topic('software_versions')
    .collectFile(name: 'all_versions.txt', newLine: true)
  
  // Collect QC statistics
  channel.topic('qc_stats')
    .groupTuple(by: 0)
}
```

---

## 3. Project Structure

### nf-core Standard Structure (2024-2025)
```
pipeline-name/
├── .github/workflows/     # CI/CD workflows
├── assets/               # Pipeline assets
│   ├── schema_input.json
│   └── samplesheet.csv
├── bin/                  # Executable scripts
├── conf/                 # Configuration files
│   ├── base.config
│   ├── modules.config
│   └── test.config
├── docs/                 # Documentation
├── modules/              # Pipeline modules
│   ├── local/           # Custom modules
│   └── nf-core/         # Community modules
├── subworkflows/         # Reusable workflows
│   ├── local/
│   └── nf-core/
├── workflows/            # Main workflow
│   └── pipeline_name.nf
├── main.nf              # Entry point
├── nextflow.config      # Main configuration
├── nextflow_schema.json # Parameter schema
└── modules.json         # Module tracking
```

### Main Configuration (nextflow.config)
```groovy
manifest {
    name            = 'nf-core/pipeline'
    author          = 'Author Name'
    homePage        = 'https://github.com/nf-core/pipeline'
    mainScript      = 'main.nf'
    nextflowVersion = '!>=24.04.0'
    version         = '1.0.0'
    defaultBranch   = 'main'
}

params {
    // Input/output
    input     = null
    outdir    = null
    
    // Process options
    skip_fastqc = false
    
    // Resource limits (NEW 2024)
    max_memory = '128.GB'
    max_cpus   = 16
    max_time   = '240.h'
}

// Resource limits (replaces check_max)
resourceLimits {
    memory = params.max_memory
    cpus   = params.max_cpus
    time   = params.max_time
}

process {
    withName: 'FASTQC' {
        cpus   = { 2 * task.attempt }
        memory = { 4.GB * task.attempt }
        time   = { 4.h * task.attempt }
    }
}

profiles {
    docker {
        docker.enabled = true
        docker.runOptions = '-u $(id -u):$(id -g)'
    }
    
    // NEW: Wave profile
    wave {
        wave.enabled = true
        wave.freeze = true
        wave.strategy = 'conda,container'
    }
}

// NEW: Plugin configuration
plugins {
    id 'nf-schema@2.2.0'
}
```

### Module Structure
```
modules/local/tool_name/
├── main.nf           # Module logic
├── meta.yml          # Module metadata
└── tests/            # nf-test tests
    ├── main.nf.test
    ├── main.nf.test.snap
    └── tags.yml
```

---

## 4. Resume & Checkpoints

### Basic Resume Usage
```bash
# Run with resume
nextflow run pipeline.nf -resume

# Resume specific session
nextflow run pipeline.nf -resume <SESSION_ID>

# Enable lineage tracking (25.04+)
# In nextflow.config:
lineage {
    enabled = true
    path = '.lineage'
}
```

### Cloud Cache Configuration
```bash
# AWS S3
export NXF_CLOUDCACHE_PATH="s3://my-bucket/cache"

# Azure Blob Storage
export NXF_CLOUDCACHE_PATH="az://container/.cache"

# Google Cloud Storage
export NXF_CLOUDCACHE_PATH="gs://bucket/.cache"
```

### Resume Strategy Configuration
```groovy
process {
    // Automatic retries with resource scaling
    errorStrategy = { task.exitStatus in [143,137,104,134,139,140] ? 'retry' : 'finish' }
    maxRetries = 3
    
    // Dynamic resource allocation
    cpus = { 2 * task.attempt }
    memory = { 4.GB * task.attempt }
    
    // Cache strategy for NFS
    cache = 'lenient'
}
```

### Troubleshooting Resume
```bash
# Debug hash differences
nextflow -log initial.log run pipeline -dump-hashes json
nextflow -log resumed.log run pipeline -dump-hashes json -resume

# Compare with lineage (25.04+)
nextflow lineage diff lid://<RUN1_HASH> lid://<RUN2_HASH>

# View specific task
nextflow lineage view lid://<TASK_HASH>

# Clean specific runs
nextflow clean <RUN_NAME> -f
nextflow clean -before <RUN_NAME> -n  # Dry run
```

### Data Lineage Access
```groovy
workflow incremental_analysis {
    // Get baseline results
    baseline_data = channel.fromLineage(
        workflowRun: 'lid://baseline_run_id',
        label: ['reference_set', 'calibration_data']
    )
    
    new_samples = channel.fromPath('new_data/*.fastq')
    comparative_analysis(new_samples, baseline_data)
}
```

---

## 5. Testing Strategies

### nf-test Installation
```bash
# Install nf-test
curl -fsSL https://code.askimed.com/install/nf-test | bash

# Or via Bioconda
conda install -c bioconda nf-test
```

### Process Testing
```groovy
// tests/modules/local/process.nf.test
nextflow_process {
    name "Test Process FASTQC"
    script "../main.nf"
    process "FASTQC"
    
    test("Single-end reads") {
        when {
            process {
                """
                input[0] = [
                    [ id:'test', single_end:true ],
                    file(params.test_data['sarscov2']['illumina']['test_1_fastq_gz'])
                ]
                """
            }
        }
        
        then {
            assertAll(
                { assert process.success },
                { assert snapshot(process.out).match() }
            )
        }
    }
}
```

### Pipeline Testing
```groovy
// tests/main.nf.test
nextflow_pipeline {
    name "Test Complete Pipeline"
    script "main.nf"
    
    test("Full pipeline test") {
        when {
            params {
                input = "${projectDir}/test_data/samplesheet.csv"
                outdir = "results"
                genome = "GRCh38"
            }
        }
        
        then {
            assert workflow.success
            assert workflow.trace.tasks().size() >= 10
            assert path("${params.outdir}/multiqc/multiqc_report.html").exists()
            assert snapshot(workflow.out.versions).match()
        }
    }
}
```

### CI/CD Configuration
```yaml
# .github/workflows/ci.yml
name: nf-test CI
on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        NXF_VER: ["23.04.0", "latest-everything"]
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install Nextflow
      uses: nf-core/setup-nextflow@v1
      with:
        version: ${{ matrix.NXF_VER }}
    
    - name: Setup nf-test
      run: |
        wget -qO- https://code.askimed.com/install/nf-test | bash
        sudo mv nf-test /usr/local/bin/
    
    - name: Run nf-test
      run: nf-test test --profile docker --verbose
```

### Test Configuration
```groovy
// nf-test.config
config {
    testsDir "tests"
    workDir ".nf-test"
    configFile "tests/nextflow.config"
    profile "docker"
    
    // Enable parallel execution
    maxForks 4
    
    options {
        verbose = true
        cleanup = true
    }
}
```

### Snapshot Testing
```groovy
test("Should produce consistent output") {
    when {
        process {
            """
            input[0] = file("${projectDir}/test_data/input.txt")
            """
        }
    }
    
    then {
        // Create snapshot of all outputs
        assert snapshot(process.out).match()
        
        // Named snapshots
        assert snapshot(process.out.results).match("results")
        assert snapshot(process.out.logs).match("logs")
    }
}
```

---

## 6. Quick Reference Commands

### Pipeline Execution
```bash
# Basic execution
nextflow run main.nf
nextflow run main.nf -profile docker
nextflow run main.nf -resume
nextflow run main.nf -resume <SESSION_ID>

# With parameters
nextflow run main.nf --input data.csv --outdir results

# Background execution
nextflow run main.nf -bg > pipeline.log 2>&1
```

### Environment Management (Pixi)
```bash
# Install/update
pixi install
pixi update
pixi install --frozen  # From lockfile

# Environment activation
pixi shell            # Default env
pixi shell -e production
pixi run <command>    # Run in env
pixi exec <command>   # Single command
```

### Monitoring & Debugging
```bash
# View logs
nextflow log
nextflow log <RUN_NAME>

# Generate reports
nextflow run main.nf -with-report report.html
nextflow run main.nf -with-trace trace.txt
nextflow run main.nf -with-timeline timeline.html
nextflow run main.nf -with-dag dag.svg

# Debug hashes
nextflow run main.nf -dump-hashes json

# Lineage operations (25.04+)
nextflow lineage list
nextflow lineage view lid://<HASH>
nextflow lineage find params.genome=GRCh38
```

### Cleanup
```bash
# Clean work directory
nextflow clean -f
nextflow clean <RUN_NAME> -f
nextflow clean -before <DATE> -f
nextflow clean -after <DATE> -f
nextflow clean -keep-logs <RUN_NAME>

# Pixi cleanup
rm -rf .pixi/
pixi clean
```

### Testing
```bash
# Run tests
nf-test test
nf-test test --profile docker
nf-test test tests/modules/
nf-test test --tag fastqc

# Update snapshots
nf-test test --update-snapshot
```

### Configuration
```groovy
// Enable new features
nextflow.enable.dsl = 2  // DSL2 syntax
nextflow.preview.topic = true  // Topic channels (24.04)

// Resource management
process.cpus = 4
process.memory = '8 GB'
process.time = '2 h'
process.errorStrategy = 'retry'
process.maxRetries = 3

// Execution
executor.queueSize = 100
executor.pollInterval = '10 sec'
executor.dumpInterval = '30 sec'
```

### Key Environment Variables
```bash
NXF_VER=25.04.6              # Nextflow version
NXF_CLOUDCACHE_PATH=s3://... # Cloud cache location
NXF_JVM_ARGS="-Xms2g -Xmx8g" # JVM settings
NXF_ANSI_LOG=false           # Disable ANSI in logs
NXF_SYNTAX_PARSER=v2         # Enable strict syntax
JAVA_HOME=/path/to/java17    # Java location
```

## Summary

This cheatsheet covers the latest Nextflow features and best practices from 2024-2025:

- **Topic Channels**: New pub/sub messaging pattern for simplified metadata collection
- **Data Lineage**: Built-in provenance tracking with `channel.fromLineage()`
- **Resource Limits**: Native `resourceLimits` replacing `check_max()`
- **nf-test Framework**: Comprehensive testing with snapshot support
- **Pixi Package Manager**: 3-10x faster than conda with automatic lockfiles
- **Enhanced Resume**: Cloud cache support and improved debugging tools

For AI agents working with Nextflow, focus on:
1. Using topic channels for metadata aggregation
2. Implementing proper test coverage with nf-test
3. Following nf-core project structure standards
4. Leveraging data lineage for reproducibility
5. Using Pixi for fast, reproducible environments
