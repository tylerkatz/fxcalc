package main

import (
	"fmt"
	"image/color"
	"strconv"
	"strings"

	"github.com/tylerkatz/fxcalc/trade"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

// FX pair structure
type FXPair struct {
	name          string
	baseCurrency  string
	quoteCurrency string
}

func main() {
	myApp := app.New()
	window := myApp.NewWindow("fxcalc")

	// Define currency pairs
	fxPairs := []FXPair{
		{"EUR/USD", "EUR", "USD"},
		{"GBP/USD", "GBP", "USD"},
		{"USD/JPY", "USD", "JPY"},
		{"XAU/USD", "XAU", "USD"},
		{"USD/CHF", "USD", "CHF"},
		{"AUD/USD", "AUD", "USD"},
		{"USD/CAD", "USD", "CAD"},
		{"NZD/USD", "NZD", "USD"},
		{"EUR/GBP", "EUR", "GBP"},
		{"EUR/JPY", "EUR", "JPY"},
		{"GBP/JPY", "GBP", "JPY"},
		{"AUD/JPY", "AUD", "JPY"},
		{"EUR/CHF", "EUR", "CHF"},
		{"GBP/CHF", "GBP", "CHF"},
		{"EUR/AUD", "EUR", "AUD"},
		{"EUR/CAD", "EUR", "CAD"},
		{"AUD/CAD", "AUD", "CAD"},
		{"AUD/NZD", "AUD", "NZD"},
		{"USD/SGD", "USD", "SGD"},
		{"USD/HKD", "USD", "HKD"},
		{"USD/CNH", "USD", "CNH"},
	}

	// Available account currencies
	accountCurrencies := []string{"USD", "EUR", "GBP", "JPY", "CHF", "AUD", "CAD", "NZD"}

	// Leverage options
	leverageOptions := []string{
		"1:1", "2:1", "5:1", "10:1", "20:1", "50:1", "100:1", "500:1",
		"1000:1", "2000:1", "3000:1",
	}

	// Create widgets
	accountCurrencySelect := widget.NewSelect(accountCurrencies, nil)
	accountCurrencySelect.SetSelected("USD")

	leverageSelect := widget.NewSelect(leverageOptions, nil)
	leverageSelect.SetSelected("2000:1")

	availableMarginEntry := widget.NewEntry()
	availableMarginEntry.SetPlaceHolder("Available margin")

	instrumentSelect := widget.NewSelect(
		func() []string {
			var names []string
			for _, pair := range fxPairs {
				names = append(names, pair.name)
			}
			return names
		}(),
		nil,
	)
	instrumentSelect.SetSelected("EUR/USD")

	riskAmountHomeCurrency := widget.NewEntry()
	riskAmountHomeCurrency.SetPlaceHolder("Risk amount in account currency")

	riskAmountPips := widget.NewEntry()
	riskAmountPips.SetPlaceHolder("Risk amount in PIPs")

	highPriceEntry := widget.NewEntry()
	highPriceEntry.SetPlaceHolder("High price")
	lowPriceEntry := widget.NewEntry()
	lowPriceEntry.SetPlaceHolder("Low price")

	// Result labels
	positionLabel := widget.NewHyperlink("Position Size: ", nil)
	positionLabel.TextStyle = fyne.TextStyle{Bold: true}

	highPositionLabel := widget.NewHyperlink("Position Size [High Price]: ", nil)
	highPositionLabel.TextStyle = fyne.TextStyle{Bold: true}

	lowPositionLabel := widget.NewHyperlink("Position Size [Low Price]: ", nil)
	lowPositionLabel.TextStyle = fyne.TextStyle{Bold: true}

	avgPositionLabel := widget.NewHyperlink("Position Size [Average Price]: ", nil)
	avgPositionLabel.TextStyle = fyne.TextStyle{Bold: true}

	// Add new labels for additional info
	maxPositionLabel := widget.NewLabel("Maximum Position: ")
	pipValueLabel := widget.NewLabel("Pip Value: ")

	// Create error label with red color
	errorLabel := canvas.NewText("", color.RGBA{R: 255, G: 0, B: 0, A: 255})
	errorLabel.TextStyle.Bold = true

	// Declare riskLabel with initial account currency
	riskLabel := widget.NewLabelWithStyle(
		fmt.Sprintf("Risk Amount (%s)", accountCurrencySelect.Selected),
		fyne.TextAlignLeading,
		fyne.TextStyle{Italic: true},
	)

	// Function to check if price inputs should be disabled
	updatePriceInputs := func() {
		var selectedPair FXPair
		for _, pair := range fxPairs {
			if pair.name == instrumentSelect.Selected {
				selectedPair = pair
				break
			}
		}

		// Only disable price inputs when base currency matches account currency
		shouldDisable := selectedPair.baseCurrency == accountCurrencySelect.Selected

		if shouldDisable {
			highPriceEntry.Disable()
			lowPriceEntry.Disable()
			highPriceEntry.SetText("1.0")
			lowPriceEntry.SetText("1.0")
		} else {
			highPriceEntry.Enable()
			lowPriceEntry.Enable()
			highPriceEntry.SetText("")
			lowPriceEntry.SetText("")
		}
	}

	// Set up OnChanged handler AFTER both widgets are created
	accountCurrencySelect.OnChanged = func(s string) {
		updatePriceInputs()
		riskLabel.SetText(fmt.Sprintf("Risk Amount (%s)", s))
	}

	// Add OnChanged handlers
	instrumentSelect.OnChanged = func(s string) {
		updatePriceInputs()
	}

	// Call immediately to handle initial state
	updatePriceInputs()

	// Function to show trade details popup
	showTradeDetails := func(units int, pipValue float64, leverage float64, basePrice float64, maxUnits int) {
		marginUsed := (float64(units) * basePrice) / leverage
		riskAmount, _ := strconv.ParseFloat(riskAmountHomeCurrency.Text, 64)
		availableMargin, _ := strconv.ParseFloat(availableMarginEntry.Text, 64)
		wcma := availableMargin - marginUsed - riskAmount

		detailsPopup := widget.NewPopUp(
			container.NewVBox(
				widget.NewLabel(fmt.Sprintf("Units: %d", units)),
				widget.NewLabel(fmt.Sprintf("Max Units: %d", maxUnits)),
				widget.NewLabel(fmt.Sprintf("Position Utilization: %.1f%% of MAX", (float64(units)/float64(maxUnits))*100)),
				widget.NewLabel(fmt.Sprintf("Pip Value: %.2f %s", pipValue, accountCurrencySelect.Selected)),
				widget.NewLabel(fmt.Sprintf("Margin Used: %.2f %s", marginUsed, accountCurrencySelect.Selected)),
				widget.NewLabel(fmt.Sprintf("WCMA: %.2f %s", wcma, accountCurrencySelect.Selected)),
			),
			window.Canvas(),
		)

		// Get the window size
		windowSize := window.Canvas().Size()

		// Position the popup in the bottom right
		detailsPopup.Move(fyne.NewPos(
			windowSize.Width-detailsPopup.MinSize().Width-10,   // 10 pixels from right edge
			windowSize.Height-detailsPopup.MinSize().Height-10, // 10 pixels from bottom edge
		))

		detailsPopup.Show()
	}

	// Function to hide all result labels
	hideResults := func() {
		highPositionLabel.Hide()
		lowPositionLabel.Hide()
		avgPositionLabel.Hide()
	}

	// Calculate button with styling
	btn := widget.NewButton("Calculate", func() {
		// Parse inputs
		availableMargin, err1 := strconv.ParseFloat(availableMarginEntry.Text, 64)
		riskAmount, err2 := strconv.ParseFloat(riskAmountHomeCurrency.Text, 64)
		stopLoss, err3 := strconv.ParseFloat(riskAmountPips.Text, 64)
		highPrice, err4 := strconv.ParseFloat(highPriceEntry.Text, 64)
		lowPrice, err5 := strconv.ParseFloat(lowPriceEntry.Text, 64)

		// Basic validation
		if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil {
			errorLabel.Text = "Please enter valid numbers"
			hideResults()
			return
		}

		// Value validation
		if availableMargin <= 0 {
			errorLabel.Text = "Available margin must be positive"
			hideResults()
			return
		}
		if riskAmount <= 0 || riskAmount > availableMargin {
			errorLabel.Text = "Risk amount must be positive and less than available margin"
			hideResults()
			return
		}
		if stopLoss <= 0 {
			errorLabel.Text = "Stop loss must be positive"
			hideResults()
			return
		}
		if highPrice <= 0 || lowPrice <= 0 {
			errorLabel.Text = "Prices must be positive"
			hideResults()
			return
		}
		if lowPrice > highPrice {
			errorLabel.Text = "Low price cannot be higher than high price"
			hideResults()
			return
		}

		// Parse leverage
		leverageStr := strings.Split(leverageSelect.Selected, ":")[0]
		leverage, _ := strconv.ParseFloat(leverageStr, 64)

		// Get selected pair
		var selectedPair FXPair
		for _, pair := range fxPairs {
			if pair.name == instrumentSelect.Selected {
				selectedPair = pair
				break
			}
		}

		homeQuoteRate := 1.0 // Simplified - in real app would need real rates

		availableMargin, err := strconv.ParseFloat(availableMarginEntry.Text, 64)
		if err != nil {
			return
		}

		// Calculate positions
		highUnits, highPipValue, maxHighUnits, errMsg := trade.CalculatePositionDetails(
			// Account parameters
			availableMargin,
			leverage,
			riskAmount,

			// Price parameters
			highPrice,
			stopLoss,
			homeQuoteRate,

			// Currency parameters
			selectedPair.quoteCurrency,
			accountCurrencySelect.Selected,
		)

		// Check for calculation errors
		if errMsg != "" {
			errorLabel.Text = errMsg
			hideResults()
			return
		}

		// Check if position calculation was successful
		if highUnits == 0 {
			errorLabel.Text = "Position too small - try increasing risk pips or amount"
			hideResults()
			return
		}
		if highUnits < 100 {
			errorLabel.Text = "Warning: Position size very small - consider increasing risk"
		} else {
			errorLabel.Text = "" // Clear any previous errors
		}

		lowUnits, lowPipValue, maxLowUnits, errMsg2 := trade.CalculatePositionDetails(
			// Account parameters
			availableMargin,
			leverage,
			riskAmount,

			// Price parameters
			lowPrice,
			stopLoss,
			homeQuoteRate,

			// Currency parameters
			selectedPair.quoteCurrency,
			accountCurrencySelect.Selected,
		)

		// Check low price calculation errors
		if errMsg2 != "" {
			errorLabel.Text = errMsg2
			hideResults()
			return
		}

		avgUnits := (highUnits + lowUnits) / 2
		avgPipValue := (highPipValue + lowPipValue) / 2
		maxUnits := (maxHighUnits + maxLowUnits) / 2

		// Always show all three position sizes
		highPositionLabel.Show()
		lowPositionLabel.Show()
		avgPositionLabel.Show()

		if selectedPair.baseCurrency == accountCurrencySelect.Selected {
			// When base currency matches account currency, show only average position
			highPositionLabel.Hide()
			lowPositionLabel.Hide()
			avgPositionLabel.Show()
			avgPositionLabel.SetText(fmt.Sprintf("Position Size: %d units", avgUnits))
			avgPositionLabel.OnTapped = func() {
				showTradeDetails(avgUnits, avgPipValue, leverage, (highPrice+lowPrice)/2, maxUnits)
			}
		} else {
			// Show all positions for different currencies
			highPositionLabel.Show()
			lowPositionLabel.Show()
			avgPositionLabel.Show()

			highPositionLabel.SetText(fmt.Sprintf("Position Size [High Price]: %d units", highUnits))
			avgPositionLabel.SetText(fmt.Sprintf("Position Size [Average Price]: %d units", avgUnits))
			lowPositionLabel.SetText(fmt.Sprintf("Position Size [Low Price]: %d units", lowUnits))

			highPositionLabel.OnTapped = func() {
				showTradeDetails(highUnits, highPipValue, leverage, highPrice, maxHighUnits)
			}
			lowPositionLabel.OnTapped = func() {
				showTradeDetails(lowUnits, lowPipValue, leverage, lowPrice, maxLowUnits)
			}
			avgPositionLabel.OnTapped = func() {
				showTradeDetails(avgUnits, avgPipValue, leverage, (highPrice+lowPrice)/2, maxUnits)
			}
		}

		// Simplify max position label
		maxPositionLabel.SetText(fmt.Sprintf("Maximum Position: %d units", maxUnits))

		// Remove pip value label since it's now in popup
		pipValueLabel.Hide()

		// Create labels with bold style
		positionLabel := widget.NewHyperlink("Position Size: ", nil)
		positionLabel.TextStyle = fyne.TextStyle{Bold: true}

		highPositionLabel := widget.NewHyperlink("Position Size [High Price]: ", nil)
		highPositionLabel.TextStyle = fyne.TextStyle{Bold: true}

		avgPositionLabel := widget.NewHyperlink("Position Size [Average Price]: ", nil)
		avgPositionLabel.TextStyle = fyne.TextStyle{Bold: true}

		lowPositionLabel := widget.NewHyperlink("Position Size [Low Price]: ", nil)
		lowPositionLabel.TextStyle = fyne.TextStyle{Bold: true}

		// Remove maxUnitsLabel.SetText() call
	})
	btn.Importance = widget.HighImportance // Green theme
	calculateBtn := container.NewPadded(btn)

	// Create grid layouts for each section
	accountGrid := container.NewGridWithColumns(2,
		container.NewVBox(
			widget.NewLabelWithStyle("Currency", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			accountCurrencySelect,
			widget.NewLabelWithStyle("Available Margin", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			availableMarginEntry,
		),
		container.NewVBox(
			widget.NewLabelWithStyle("Leverage", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			leverageSelect,
		),
	)

	// Account settings group
	accountGroup := container.NewVBox(
		accountGrid,
	)

	// Trade parameters layout
	tradeGroup := container.NewVBox(
		// Instrument on its own row
		container.NewVBox(
			widget.NewLabelWithStyle("Instrument", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			instrumentSelect,
		),
		// Other parameters in a grid
		container.NewGridWithColumns(2,
			container.NewVBox(
				riskLabel,
				riskAmountHomeCurrency,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("Stop Loss (PIPs)", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				riskAmountPips,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("High Price", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				highPriceEntry,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("Low Price", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				lowPriceEntry,
			),
		),
	)

	// Results group
	resultsGroup := container.NewVBox(
		positionLabel,
		highPositionLabel,
		avgPositionLabel,
		lowPositionLabel,
	)

	// Hide all labels initially
	positionLabel.Hide()
	highPositionLabel.Hide()
	avgPositionLabel.Hide()
	lowPositionLabel.Hide()
	pipValueLabel.Hide()

	// Main content layout
	content := container.NewVBox(
		widget.NewLabelWithStyle("Position Size Calculator", fyne.TextAlignCenter, fyne.TextStyle{Bold: true}),
		widget.NewSeparator(),
		container.NewPadded(widget.NewCard("Account Settings", "", accountGroup)),
		widget.NewSeparator(),
		container.NewPadded(widget.NewCard("Trade Parameters", "", tradeGroup)),
		widget.NewSeparator(),
		calculateBtn,
		container.NewPadded(errorLabel),
		container.NewPadded(widget.NewCard("Results", "", resultsGroup)),
	)

	// Adjust window size to be wider and less tall
	window.SetContent(content)
	window.Resize(fyne.NewSize(600, 900))
	window.CenterOnScreen()
	window.ShowAndRun()
}
