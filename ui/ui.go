package ui

import (
	_ "embed"
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

//go:embed assets/fxcalc_logo.png
var iconData []byte

// New creates a new UI instance
func New() *UI {
	if len(iconData) == 0 {
		panic("Icon data not loaded")
	}
	myApp := app.New()

	// Set app icon using embedded data
	icon := &fyne.StaticResource{
		StaticName:    "Icon.png",
		StaticContent: iconData,
	}
	myApp.SetIcon(icon)

	window := myApp.NewWindow("fxcalc")

	ui := &UI{
		window:  window,
		fxPairs: GetFXPairs(),
		widgets: createWidgets(),
	}

	ui.setupCallbacks()
	ui.createLayout()

	return ui
}

// Run starts the UI
func (ui *UI) Run() {
	ui.window.Resize(fyne.NewSize(600, 900))
	ui.window.CenterOnScreen()
	ui.window.ShowAndRun()
}

func createWidgets() *Widgets {
	w := &Widgets{
		accountCurrencySelect:  widget.NewSelect(GetAccountCurrencies(), nil),
		leverageSelect:         widget.NewSelect(GetLeverageOptions(), nil),
		availableMarginEntry:   widget.NewEntry(),
		instrumentSelect:       widget.NewSelect(getPairNames(), nil),
		riskAmountHomeCurrency: widget.NewEntry(),
		riskAmountPips:         widget.NewEntry(),
		highPriceEntry:         widget.NewEntry(),
		lowPriceEntry:          widget.NewEntry(),
		errorLabel:             canvas.NewText("", color.NRGBA{R: 255, A: 255}),
		positionLabel:          widget.NewHyperlink("Position Size: ", nil),
		highPositionLabel:      widget.NewHyperlink("Position Size [High Price]: ", nil),
		lowPositionLabel:       widget.NewHyperlink("Position Size [Low Price]: ", nil),
		avgPositionLabel:       widget.NewHyperlink("Position Size [Average Price]: ", nil),
		maxPositionLabel:       widget.NewLabel("Maximum Position: "),
		pipValueLabel:          widget.NewLabel("Pip Value: "),
		riskLabel: widget.NewLabelWithStyle(
			fmt.Sprintf("Risk Amount (%s)", "USD"),
			fyne.TextAlignLeading,
			fyne.TextStyle{Italic: true},
		),
	}

	// Set initial styles and states
	w.positionLabel.TextStyle = fyne.TextStyle{Bold: true}
	w.highPositionLabel.TextStyle = fyne.TextStyle{Bold: true}
	w.lowPositionLabel.TextStyle = fyne.TextStyle{Bold: true}
	w.avgPositionLabel.TextStyle = fyne.TextStyle{Bold: true}

	// Hide result labels initially
	w.positionLabel.Hide()
	w.highPositionLabel.Hide()
	w.avgPositionLabel.Hide()
	w.lowPositionLabel.Hide()
	w.pipValueLabel.Hide()

	// Set initial selections
	w.accountCurrencySelect.SetSelected("USD")
	w.leverageSelect.SetSelected("2000:1")
	w.instrumentSelect.SetSelected("EUR/USD")

	// Set placeholders
	w.availableMarginEntry.SetPlaceHolder("Available margin")
	w.riskAmountHomeCurrency.SetPlaceHolder("Risk amount in account currency")
	w.riskAmountPips.SetPlaceHolder("Risk amount in PIPs")
	w.highPriceEntry.SetPlaceHolder("High price")
	w.lowPriceEntry.SetPlaceHolder("Low price")

	return w
}

// Add helper function to get pair names
func getPairNames() []string {
	pairs := GetFXPairs()
	names := make([]string, len(pairs))
	for i, pair := range pairs {
		names[i] = pair.name
	}
	return names
}

func (ui *UI) setupCallbacks() {
	w := ui.widgets

	// Update price inputs when account currency or instrument changes
	updatePriceInputs := func() {
		var selectedPair FXPair
		for _, pair := range ui.fxPairs {
			if pair.name == w.instrumentSelect.Selected {
				selectedPair = pair
				break
			}
		}

		shouldDisable := selectedPair.baseCurrency == w.accountCurrencySelect.Selected
		if shouldDisable {
			w.highPriceEntry.Disable()
			w.lowPriceEntry.Disable()
			w.highPriceEntry.SetText("1.0")
			w.lowPriceEntry.SetText("1.0")
		} else {
			w.highPriceEntry.Enable()
			w.lowPriceEntry.Enable()
			w.highPriceEntry.SetText("")
			w.lowPriceEntry.SetText("")
		}
	}

	w.accountCurrencySelect.OnChanged = func(s string) {
		updatePriceInputs()
		w.riskLabel.SetText(fmt.Sprintf("Risk Amount (%s)", s))
	}

	w.instrumentSelect.OnChanged = func(s string) {
		updatePriceInputs()
	}

	// Call immediately to handle initial state
	updatePriceInputs()
}

func (ui *UI) createLayout() {
	w := ui.widgets

	// Create calculate button with styling
	calculateBtn := widget.NewButton("Calculate", ui.handleCalculate)
	calculateBtn.Importance = widget.HighImportance
	calculateBtnContainer := container.NewPadded(calculateBtn)

	// Account settings grid
	accountGrid := container.NewGridWithColumns(2,
		container.NewVBox(
			widget.NewLabelWithStyle("Currency", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			w.accountCurrencySelect,
			widget.NewLabelWithStyle("Available Margin", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			w.availableMarginEntry,
		),
		container.NewVBox(
			widget.NewLabelWithStyle("Leverage", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			w.leverageSelect,
		),
	)

	// Trade parameters layout
	tradeGroup := container.NewVBox(
		container.NewVBox(
			widget.NewLabelWithStyle("Instrument", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
			w.instrumentSelect,
		),
		container.NewGridWithColumns(2,
			container.NewVBox(
				w.riskLabel,
				w.riskAmountHomeCurrency,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("Stop Loss (PIPs)", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				w.riskAmountPips,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("High Price", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				w.highPriceEntry,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("Low Price", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				w.lowPriceEntry,
			),
		),
	)

	// Results group
	resultsGroup := container.NewVBox(
		w.positionLabel,
		w.highPositionLabel,
		w.avgPositionLabel,
		w.lowPositionLabel,
	)

	// Main content layout
	content := container.NewVBox(
		widget.NewLabelWithStyle("Position Size Calculator", fyne.TextAlignCenter, fyne.TextStyle{Bold: true}),
		widget.NewSeparator(),
		container.NewPadded(widget.NewCard("Account Settings", "", accountGrid)),
		widget.NewSeparator(),
		container.NewPadded(widget.NewCard("Trade Parameters", "", tradeGroup)),
		widget.NewSeparator(),
		calculateBtnContainer,
		container.NewPadded(w.errorLabel),
		container.NewPadded(widget.NewCard("Results", "", resultsGroup)),
	)

	ui.window.SetContent(content)
}

func (ui *UI) handleCalculate() {
	w := ui.widgets
	hideResults := func() {
		w.highPositionLabel.Hide()
		w.lowPositionLabel.Hide()
		w.avgPositionLabel.Hide()
	}

	// Parse inputs
	availableMargin, err1 := strconv.ParseFloat(w.availableMarginEntry.Text, 64)
	riskAmount, err2 := strconv.ParseFloat(w.riskAmountHomeCurrency.Text, 64)
	stopLoss, err3 := strconv.ParseFloat(w.riskAmountPips.Text, 64)
	highPrice, err4 := strconv.ParseFloat(w.highPriceEntry.Text, 64)
	lowPrice, err5 := strconv.ParseFloat(w.lowPriceEntry.Text, 64)

	// Basic validation
	if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil {
		w.errorLabel.Text = "Please enter valid numbers"
		hideResults()
		return
	}

	// Value validation
	if availableMargin <= 0 {
		w.errorLabel.Text = "Available margin must be positive"
		hideResults()
		return
	}
	if riskAmount <= 0 || riskAmount > availableMargin {
		w.errorLabel.Text = "Risk amount must be positive and less than available margin"
		hideResults()
		return
	}
	if stopLoss <= 0 {
		w.errorLabel.Text = "Stop loss must be positive"
		hideResults()
		return
	}
	if highPrice <= 0 || lowPrice <= 0 {
		w.errorLabel.Text = "Prices must be positive"
		hideResults()
		return
	}
	if lowPrice > highPrice {
		w.errorLabel.Text = "Low price cannot be higher than high price"
		hideResults()
		return
	}

	// Parse leverage
	leverageStr := strings.Split(w.leverageSelect.Selected, ":")[0]
	leverage, _ := strconv.ParseFloat(leverageStr, 64)

	// Get selected pair
	var selectedPair FXPair
	for _, pair := range ui.fxPairs {
		if pair.name == w.instrumentSelect.Selected {
			selectedPair = pair
			break
		}
	}

	homeQuoteRate := 1.0 // Simplified

	// Calculate positions using trade package
	highUnits, highPipValue, maxHighUnits, errMsg := trade.CalculatePositionDetails(
		availableMargin, leverage, riskAmount,
		highPrice, stopLoss, homeQuoteRate,
		selectedPair.quoteCurrency,
		w.accountCurrencySelect.Selected,
	)

	if errMsg != "" {
		w.errorLabel.Text = errMsg
		hideResults()
		return
	}

	// Check if position calculation was successful
	if highUnits == 0 {
		w.errorLabel.Text = "Position too small - try increasing risk pips or amount"
		hideResults()
		return
	}
	if highUnits < 100 {
		w.errorLabel.Text = "Warning: Position size very small - consider increasing risk"
	} else {
		w.errorLabel.Text = "" // Clear any previous errors
	}

	lowUnits, lowPipValue, maxLowUnits, errMsg2 := trade.CalculatePositionDetails(
		availableMargin, leverage, riskAmount,
		lowPrice, stopLoss, homeQuoteRate,
		selectedPair.quoteCurrency,
		w.accountCurrencySelect.Selected,
	)

	if errMsg2 != "" {
		w.errorLabel.Text = errMsg2
		hideResults()
		return
	}

	avgUnits := (highUnits + lowUnits) / 2
	avgPipValue := (highPipValue + lowPipValue) / 2
	maxUnits := (maxHighUnits + maxLowUnits) / 2

	// Always show all three position sizes
	w.highPositionLabel.Show()
	w.lowPositionLabel.Show()
	w.avgPositionLabel.Show()

	showTradeDetails := func(units int, pipValue float64, basePrice float64, maxUnits int) {
		marginUsed := (float64(units) * basePrice) / leverage
		wcma := availableMargin - marginUsed - riskAmount

		detailsPopup := widget.NewPopUp(
			container.NewVBox(
				widget.NewLabel(fmt.Sprintf("Units: %d", units)),
				widget.NewLabel(fmt.Sprintf("Max Units: %d", maxUnits)),
				widget.NewLabel(fmt.Sprintf("Position Utilization: %.1f%% of MAX", (float64(units)/float64(maxUnits))*100)),
				widget.NewLabel(fmt.Sprintf("Pip Value: %.2f %s", pipValue, w.accountCurrencySelect.Selected)),
				widget.NewLabel(fmt.Sprintf("Margin Used: %.2f %s", marginUsed, w.accountCurrencySelect.Selected)),
				widget.NewLabel(fmt.Sprintf("WCMA: %.2f %s", wcma, w.accountCurrencySelect.Selected)),
			),
			ui.window.Canvas(),
		)

		windowSize := ui.window.Canvas().Size()
		detailsPopup.Move(fyne.NewPos(
			windowSize.Width-detailsPopup.MinSize().Width-10,
			windowSize.Height-detailsPopup.MinSize().Height-10,
		))
		detailsPopup.Show()
	}

	if selectedPair.baseCurrency == w.accountCurrencySelect.Selected {
		// When base currency matches account currency, show only average position
		w.highPositionLabel.Hide()
		w.lowPositionLabel.Hide()
		w.avgPositionLabel.Show()
		w.avgPositionLabel.SetText(fmt.Sprintf("Position Size: %d units", avgUnits))
		w.avgPositionLabel.OnTapped = func() {
			showTradeDetails(avgUnits, avgPipValue, (highPrice+lowPrice)/2, maxUnits)
		}
	} else {
		// Show all positions for different currencies
		w.highPositionLabel.Show()
		w.lowPositionLabel.Show()
		w.avgPositionLabel.Show()

		w.highPositionLabel.SetText(fmt.Sprintf("Position Size [High Price]: %d units", highUnits))
		w.avgPositionLabel.SetText(fmt.Sprintf("Position Size [Average Price]: %d units", avgUnits))
		w.lowPositionLabel.SetText(fmt.Sprintf("Position Size [Low Price]: %d units", lowUnits))

		w.highPositionLabel.OnTapped = func() {
			showTradeDetails(highUnits, highPipValue, highPrice, maxHighUnits)
		}
		w.lowPositionLabel.OnTapped = func() {
			showTradeDetails(lowUnits, lowPipValue, lowPrice, maxLowUnits)
		}
		w.avgPositionLabel.OnTapped = func() {
			showTradeDetails(avgUnits, avgPipValue, (highPrice+lowPrice)/2, maxUnits)
		}
	}

	// Update max position label and hide pip value
	w.maxPositionLabel.SetText(fmt.Sprintf("Maximum Position: %d units", maxUnits))
	w.pipValueLabel.Hide()
}
