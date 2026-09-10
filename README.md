# AIAAR - Auction Assistant Scaffold - Make.com Implementation

This repository is a 2025 Make.com scaffold for auction discovery, bidding, inventory management, and resale experiments on eBay. It is not documented here as a production deployment.

## Overview

This project contains configuration, documentation, and helper scripts for a parallel product prototype built around Make.com scenarios.

## Features

- **Automated Auction Discovery**: Continuous monitoring and filtering of viable auction items
- **AI-Powered Analysis**: OpenAI integration for item valuation and market research
- **Smart Bidding**: Strategic bidding algorithms with risk management
- **Inventory Management**: Complete tracking from purchase to sale
- **Automated Resale**: Optimized listing creation and sales management
- **Analytics & Reporting**: Comprehensive performance tracking and insights

## Project Structure

```
├── make-scenarios/          # Make.com scenario configurations
├── api-modules/            # Reusable API integration modules
├── database/               # Airtable schema and setup
├── config/                 # Configuration templates
├── docs/                   # Implementation guides
├── scripts/                # Helper scripts
└── examples/               # Example configurations
```

## Quick Start

1. Clone this repository
2. Copy `.env.example` to `.env`
3. (Optional) Copy `config/environment.template.yml` to `config/environment.yml` for non-secret settings that are not already set in `.env`
4. Run `./scripts/health-check.sh`
5. Follow the setup guide in `docs/setup-guide.md`

## Run locally

1. From the repository root, create a local secrets file:
   - `cp .env.example .env`
2. Edit `.env` and replace placeholder values with your own credentials.
3. If you want to customize non-secret defaults such as sandbox mode or webhook URLs that are not already set in `.env`, copy:
   - `cp config/environment.template.yml config/environment.yml`
   - `.env` remains the source of truth for secrets and any values already defined there.
4. Run the dry-run command first:
   - `./scripts/health-check.sh`
   - This prints the live setup actions it would take and skips the live API calls.
5. When you are ready to exercise live integrations, run:
   - `./scripts/setup.sh`

## Dry run

- `./scripts/health-check.sh`
- Equivalent direct command: `./scripts/setup.sh --dry-run`
- The dry run never calls Airtable, eBay, or OpenAI. It only reports what the live setup would do.

## Error Handling & Troubleshooting

This project implements robust error handling across all automation scripts and Make.com scenarios. All shell scripts use `set -euo pipefail` and comprehensive logging to minimize silent failures.

**🚨 If you encounter issues, check the [Troubleshooting Guide](docs/troubleshooting.md) first** - it contains detailed solutions for common problems and our complete error handling strategy.

**Error logs are located in:**
- `logs/setup.log` - General setup activities
- `logs/setup_errors.log` - Detailed error information

## Documentation

- [Setup Guide](docs/setup-guide.md)
- [API Configuration](docs/api-configuration.md)
- [Make.com Scenarios](docs/scenarios-guide.md)
- [Database Schema](docs/database-schema.md)
- **[Troubleshooting Guide](docs/troubleshooting.md)** ⭐ Start here for error resolution

## License

MIT License - see [LICENSE](LICENSE) for details.