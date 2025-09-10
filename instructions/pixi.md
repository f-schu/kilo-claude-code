# Pixi.toml cheatsheet for AI agents

This comprehensive cheatsheet provides AI agents with essential patterns, configurations, and best practices for working with pixi.toml files based on 2024-2025 documentation and updates. Pixi is a modern, Rust-based package manager that unifies conda and PyPI ecosystems with superior dependency resolution and multi-environment support.

## Quick start: Essential configuration patterns

### Basic project setup with PyPI integration

The fundamental pixi.toml structure combines conda and PyPI dependencies in a single configuration file. Always specify Python in conda dependencies when using PyPI packages:

```toml
[project]
name = "my-project"
version = "0.1.0"
channels = ["conda-forge"]
platforms = ["linux-64"]

[dependencies]
python = ">=3.9"  # Required for PyPI packages

[pypi-dependencies]
fastapi = ">=0.104.0"
pandas = ">=2.0.0"
custom-package = { git = "https://github.com/user/repo.git" }
local-package = { path = "./local_package", editable = true }
```

### Multi-environment configuration for development workflows

Modern pixi projects leverage features and environments for flexible dependency management. This pattern separates development, testing, and production dependencies:

```toml
[feature.dev.dependencies]
pytest = ">=7.0.0"
black = ">=23.0.0"
ruff = ">=0.1.0"

[feature.prod.dependencies]
gunicorn = ">=21.0.0"
psycopg2 = ">=2.9.0"

[environments]
default = ["dev"]
production = { features = ["prod"], no-default-feature = true }
test = { features = ["dev"], solve-group = "default" }
```

## PyPI section configuration guide

### Advanced PyPI dependency specifications

Pixi supports multiple PyPI dependency formats beyond simple version constraints. These patterns enable git dependencies, URL-based packages, and local development:

```toml
[pypi-dependencies]
# Package with extras
pandas = { version = ">=2.0.0", extras = ["dataframe", "sql"] }

# Git dependencies with specific commits
flask = { git = "ssh://git@github.com/pallets/flask" }
requests = { 
    git = "https://github.com/psf/requests.git", 
    rev = "0106aced5faa299e6ede89d1230bd6784f2c3660" 
}

# Direct URL to wheel files
click = { url = "https://github.com/pallets/click/releases/download/8.1.7/click-8.1.7-py3-none-any.whl" }

# Editable local packages for development
my-package = { path = "./src/my-package", editable = true }
```

### PyPI authentication and private repositories

Configure authentication for private PyPI repositories using keyring (recommended) or environment variables. The keyring approach provides secure credential management:

```toml
[pypi-options]
# Custom index configuration
index-url = "https://pypi.org/simple"
extra-index-urls = ["https://private-index.company.com/simple"]

# Force wheel-only installation for faster builds
no-build = true

# Reproducible builds by date
exclude-newer = "2024-01-01"
```

For authentication setup:
```bash
# Global keyring configuration
pixi config set pypi-config.keyring-provider subprocess --global

# Install keyring
pixi global install keyring
```

### Custom PyPI index patterns

Configure multiple PyPI indexes with strict priority ordering. Pixi uses first-match strategy for package resolution:

```toml
[pypi-options]
index-url = "https://pypi.org/simple"
extra-index-urls = [
    "https://private-index-1.com/simple",
    "https://private-index-2.com/simple"
]

# Local wheel directory
find-links = [
    { path = "./wheels" },
    { url = "https://company.com/wheels" }
]
```

## Performance optimization tweaks

### Concurrency and caching configuration

Optimize pixi performance through concurrency settings and cache management. These configurations significantly improve dependency resolution and download speeds:

```toml
# Global configuration in ~/.config/pixi/config.toml
[concurrency]
downloads = 100  # Increase for faster downloads
solves = 4      # Adjust based on CPU cores

[cache]
prefer-cache-over-gb = 1
cache-dir = "/fast/ssd/pixi-cache"  # Use SSD for cache

# Project-level optimizations
[cache-options]
link-mode = "hardlink"  # Options: copy, hardlink, symlink
clean-cache-on-install = true
```

### Channel mirrors and repodata optimization

Configure faster mirrors and optimize repodata handling for improved performance:

```toml
# Global mirror configuration
[mirrors]
"https://conda.anaconda.org/conda-forge" = [
    "https://prefix.dev/conda-forge"
]

[repodata-config]
disable-jlap = false   # Keep enabled for faster updates
disable-bzip2 = true   # Disable if not needed
disable-zstd = false   # Keep for compression
```

## Platform-specific configurations

### Linux system requirements

Configure system requirements for Linux compatibility, especially important for Manjaro and Debian systems:

```toml
[system-requirements]
linux = "4.18"  # Lower for older systems
libc = { family = "glibc", version = "2.28" }

[target.linux-64.activation]
scripts = ["linux-setup.sh"]
env = { LD_LIBRARY_PATH = "$CONDA_PREFIX/lib:$LD_LIBRARY_PATH" }

[target.linux-64.dependencies]
gcc = ">=9.0.0"
pkg-config = "*"
openssl = "*"
```

### Cross-platform environment variables

Set environment variables that work across different platforms with proper activation:

```toml
[activation.env]
PYTHONIOENCODING = "utf-8"
PYTHONNOUSERSITE = "1"
PYTHONHASHSEED = "0"  # Reproducible builds
OMP_NUM_THREADS = "1"  # Control parallelism

# Task-specific variables
[tasks]
train = {
    cmd = "python train.py",
    env = {
        CUDA_VISIBLE_DEVICES = "0,1",
        PYTORCH_CUDA_ALLOC_CONF = "max_split_size_mb:128"
    }
}
```

## Advanced features and patterns

### Task automation with dependencies

Create sophisticated task workflows using dependencies and environment variables:

```toml
[tasks]
# Simple tasks
test = "pytest"
lint = "ruff check ."
format = "ruff format ."

# Complex task chains
build = { cmd = "python -m build", depends-on = ["test", "lint"] }
docs = { cmd = "sphinx-build docs docs/_build", depends-on = ["install-docs"] }

# Environment-specific tasks
dev = { cmd = "uvicorn app:app --reload", env = { DEBUG = "1" } }

# CI/CD pipeline
ci = { depends-on = ["lint", "test", "build"] }
```

### Multi-environment ML project pattern

Configure environments for different ML frameworks and hardware configurations:

```toml
[project]
name = "ml-project"
channels = ["conda-forge", "pytorch", "nvidia"]
platforms = ["linux-64"]

[feature.torch.dependencies]
pytorch = ">=2.1.0"
torchvision = ">=0.16.0"

[feature.tf.dependencies]
tensorflow = ">=2.15.0"

[feature.cuda.dependencies]
pytorch-cuda = ">=2.1.0"
cuda-toolkit = ">=12.0"

[feature.cuda.system-requirements]
cuda = "12"

[environments]
torch-cpu = ["torch"]
torch-gpu = ["torch", "cuda"]
tf-cpu = ["tf"]
tf-gpu = ["tf", "cuda"]
```

### Production-ready web application

Complete configuration for production deployments with separate development and production environments:

```toml
[project]
name = "web-api"
version = "0.1.0"
channels = ["conda-forge"]
platforms = ["linux-64"]

[dependencies]
python = "3.11.*"
fastapi = ">=0.104.0"
uvicorn = ">=0.24.0"
postgresql = ">=15.0"

[pypi-dependencies]
sqlalchemy = { version = ">=2.0.0", extras = ["asyncio"] }
pydantic = ">=2.5.0"

[feature.dev.dependencies]
pytest = ">=7.0.0"
pre-commit = ">=3.0.0"

[feature.prod.dependencies]
gunicorn = ">=21.0.0"

[environments]
default = { features = ["dev"], solve-group = "default" }
prod = { features = ["prod"], solve-group = "default" }

[tasks]
dev = "uvicorn app:app --reload"
prod = "gunicorn app:app -w 4 -k uvicorn.workers.UvicornWorker"
migrate = "alembic upgrade head"
```

## Common patterns for AI projects

### Data science project with Jupyter

Standard configuration for data science workflows with notebook support:

```toml
[project]
name = "data-science"
channels = ["conda-forge"]
platforms = ["linux-64", "osx-arm64"]

[dependencies]
python = ">=3.9"
jupyter = ">=1.0.0"
pandas = ">=2.0.0"
numpy = ">=1.24.0"
matplotlib = ">=3.7.0"
scikit-learn = ">=1.3.0"

[pypi-dependencies]
plotly = ">=5.18.0"
streamlit = ">=1.29.0"

[tasks]
notebook = "jupyter lab"
app = "streamlit run app.py"
analyze = "python scripts/analyze.py"
```

### CLI tool development

Pattern for building command-line tools with proper packaging:

```toml
[project]
name = "cli-tool"
channels = ["conda-forge"]
platforms = ["linux-64", "osx-arm64", "win-64"]

[dependencies]
python = ">=3.9"
click = ">=8.0.0"
rich = ">=13.0.0"

[pypi-dependencies]
typer = ">=0.9.0"

[feature.dev.dependencies]
pytest = ">=7.0.0"
build = ">=1.0.0"

[tasks]
install = "pip install -e ."
build = "python -m build"
test = "pytest --cov=src tests/"
release = { cmd = "twine upload dist/*", depends-on = ["test", "build"] }
```

## Recent 2024-2025 updates

### Key improvements

Recent pixi releases have introduced significant enhancements:

- **Native PyPI resolution**: Full Rust implementation without pip shell calls
- **pyproject.toml support**: Use existing Python project files
- **Lazy resolution**: Downloads minimal metadata during resolution
- **Enhanced Git support**: Better handling of git-based dependencies
- **no-build option**: Force wheel-only installation for speed
- **exclude-newer**: Reproducible builds by date exclusion

### New configuration options

```toml
# Force wheel-only packages
[pypi-options]
no-build = true

# Reproducible builds
exclude-newer = "2024-07-01"

# Index strategy options
index-strategy = "first-match"  # or "unsafe-best-match"

# Solve groups for consistency
[environments]
test = { features = ["test"], solve-group = "main" }
prod = { features = ["prod"], solve-group = "main" }
```

## Security best practices

### Dependency pinning strategies

Implement secure dependency management with appropriate version constraints:

```toml
# Production dependencies - exact versions
[dependencies]
python = "3.11.*"
critical-package = "==1.2.3"

# Development dependencies - flexible versions
[feature.dev.dependencies]
pytest = ">=7.0.0,<8.0.0"
black = ">=23.0.0"

# Security-focused configuration
[pypi-options]
keyring-provider = "subprocess"
index-url = "https://pypi.org/simple"  # Official PyPI only
```

### Environment isolation

Create minimal production environments to reduce attack surface:

```toml
[environments]
prod = { features = [], no-default-feature = true }
dev = { features = ["dev", "test"] }

[feature.prod.dependencies]
# Only production-required packages
```

## Quick reference commands

Essential pixi commands for daily development:

```bash
# Project initialization
pixi init --format pyproject --channel conda-forge

# Dependency management
pixi add numpy pandas              # Add conda packages
pixi add --pypi requests fastapi   # Add PyPI packages
pixi add --feature dev pytest      # Add to specific feature

# Environment operations
pixi install --locked              # Reproducible install
pixi update                        # Update all dependencies
pixi run --environment prod cmd    # Run in specific environment

# Task execution
pixi run test                      # Run defined task
pixi task list                     # Show available tasks
```

This cheatsheet provides AI agents with comprehensive patterns and configurations for pixi.toml files based on the latest 2024-2025 updates. Focus on using features and environments for flexible dependency management, leverage PyPI integration for Python packages, and implement proper task automation for efficient workflows.
