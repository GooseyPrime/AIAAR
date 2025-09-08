# AIAAR - Automated Auction Assistant - Make.com Implementation

A comprehensive Make.com integration system for automated auction discovery, bidding, inventory management, and resale operations on eBay.

## Overview

This system provides a complete automated auction assistant that can run 24/7 with minimal supervision while maintaining profitability and managing risk through Make.com automation scenarios.

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
2. Follow the setup guide in `/docs/setup-guide.md`
3. Configure your API keys in `/config/environment.yml`
4. Import Make.com scenarios from `/make-scenarios/`
5. Set up Airtable database using `/database/schema.json`

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