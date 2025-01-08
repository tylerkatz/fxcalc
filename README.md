# FX Calculator

A desktop application for calculating forex position sizes with risk management features, built using Go and Fyne UI framework.

## Features

- Calculate position sizes for major forex pairs including:
  - Major pairs (EUR/USD, GBP/USD, USD/JPY)
  - Cross rates (EUR/GBP, GBP/JPY)
  - Commodity pairs (AUD/USD, USD/CAD)
  - Precious metals (XAU/USD)
- Support for multiple account base currencies (USD, EUR, GBP, etc.)
- Risk-based position sizing
- Leverage adjustment
- Pip value calculations
- Maximum position size limits
- User-friendly interface built with Fyne

## Installation

### Prerequisites

- Go 1.22 or higher
- Fyne dependencies (automatically handled by Go modules)

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/tylerkatz/fxcalc.git
cd fxcalc
```

2. Install dependencies:
```bash
go mod download
```

3. Build the application:
```bash
go build
```

### Creating Application Bundles

#### macOS
```bash
sh bundle/osx.sh
```
This will create a macOS application bundle (.app) in the current directory.

#### Windows
```bash
sh bundle/win.sh
```
This will create a Windows executable (.exe) in the current directory.

#### Linux
```bash
sh bundle/linux.sh
```
This will create a Linux binary in the current directory.

## Usage

The application provides a graphical interface for forex position sizing calculations:

1. Select your account currency from the available options
2. Enter your available margin
3. Choose your desired leverage
4. Select the forex pair you want to trade
5. Enter your risk amount
6. Specify your stop loss in pips
7. The application will calculate:
   - Position size
   - Pip value
   - Maximum allowable position

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (\`git checkout -b feature/AmazingFeature\`)
3. Commit your changes (\`git commit -m 'Add some AmazingFeature'\`)
4. Push to the branch (\`git push origin feature/AmazingFeature\`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with [Fyne](https://fyne.io/) - Cross platform GUI framework
- Inspired by professional forex trading risk management practices


## Development

The application is built using:
- Go programming language for robust backend calculations
- Fyne UI framework for cross-platform GUI
- Custom position sizing algorithms based on:
  - Account currency
  - Trading instrument
  - Risk parameters
  - Leverage settings

## Roadmap

- Change to web UI from Fyne
- Add support for strategies

## Support

For support, please open an issue in the GitHub repository or contact the maintainers.
