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

	ui := &UI{
		window:  myApp.NewWindow("FX Position Size Calculator"),
		fxPairs: GetFXPairs(),
	}

	// Create widgets first
	ui.widgets = createWidgets()

	// Create layout (which creates containers)
	ui.createLayout()

	// Setup callbacks after containers are created
	ui.setupCallbacks()

	// Set window content and show
	ui.window.Resize(fyne.NewSize(400, 600))
	ui.window.Show()

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
		// Initialize cross rate inputs
		baseHighPriceEntry:  widget.NewEntry(),
		baseLowPriceEntry:   widget.NewEntry(),
		quoteHighPriceEntry: widget.NewEntry(),
		quoteLowPriceEntry:  widget.NewEntry(),
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

	// Set all placeholders
	w.availableMarginEntry.SetPlaceHolder("50")
	w.riskAmountHomeCurrency.SetPlaceHolder("20")
	w.riskAmountPips.SetPlaceHolder("5")
	w.quoteHighPriceEntry.SetPlaceHolder("EUR/USD (high)")
	w.quoteLowPriceEntry.SetPlaceHolder("EUR/USD (low)")
	w.baseHighPriceEntry.SetPlaceHolder("EUR/USD (high)")
	w.baseLowPriceEntry.SetPlaceHolder("EUR/USD (low)")

	// Ensure entries are visible
	w.baseHighPriceEntry.Show()
	w.baseLowPriceEntry.Show()
	w.quoteHighPriceEntry.Show()
	w.quoteLowPriceEntry.Show()

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

	// Define updatePriceInputs but don't call it yet
	updatePriceInputs := func() {
		var selectedPair FXPair
		for _, pair := range ui.fxPairs {
			if pair.name == w.instrumentSelect.Selected {
				selectedPair = pair
				break
			}
		}

		// When base currency is home currency
		if selectedPair.baseCurrency == w.accountCurrencySelect.Selected {
			ui.baseContainer.Hide()
			ui.quoteContainer.Show()
			w.quoteHighPriceEntry.Enable()
			w.quoteLowPriceEntry.Enable()
			ui.quoteContainer.Objects[0].(*widget.Label).SetText(
				fmt.Sprintf("Quote/Home Price [%s/%s]",
					selectedPair.quoteCurrency,
					w.accountCurrencySelect.Selected))
			w.quoteHighPriceEntry.SetPlaceHolder(fmt.Sprintf("%s (high)", selectedPair.name))
			w.quoteLowPriceEntry.SetPlaceHolder(fmt.Sprintf("%s (low)", selectedPair.name))
		} else if selectedPair.quoteCurrency == w.accountCurrencySelect.Selected {
			ui.baseContainer.Show()
			ui.quoteContainer.Show()
			w.baseHighPriceEntry.Enable()
			w.baseLowPriceEntry.Enable()
			w.quoteHighPriceEntry.Disable()
			w.quoteLowPriceEntry.Disable()
			w.quoteHighPriceEntry.SetText("1.0")
			w.quoteLowPriceEntry.SetText("1.0")
			ui.baseContainer.Objects[0].(*widget.Label).SetText(
				fmt.Sprintf("Base/Home Price [%s/%s]",
					selectedPair.baseCurrency,
					w.accountCurrencySelect.Selected))
			ui.quoteContainer.Objects[0].(*widget.Label).SetText(
				fmt.Sprintf("Quote/Home Price [%s/%s]",
					selectedPair.quoteCurrency,
					w.accountCurrencySelect.Selected))
			w.baseHighPriceEntry.SetPlaceHolder(fmt.Sprintf("%s (high)", selectedPair.name))
			w.baseLowPriceEntry.SetPlaceHolder(fmt.Sprintf("%s (low)", selectedPair.name))
		} else {
			ui.baseContainer.Show()
			ui.quoteContainer.Show()
			w.baseHighPriceEntry.Enable()
			w.baseLowPriceEntry.Enable()
			w.quoteHighPriceEntry.Enable()
			w.quoteLowPriceEntry.Enable()
			ui.baseContainer.Objects[0].(*widget.Label).SetText(
				fmt.Sprintf("Base/Home Price [%s/%s]",
					selectedPair.baseCurrency,
					w.accountCurrencySelect.Selected))
			ui.quoteContainer.Objects[0].(*widget.Label).SetText(
				fmt.Sprintf("Quote/Home Price [%s/%s]",
					selectedPair.quoteCurrency,
					w.accountCurrencySelect.Selected))
			w.baseHighPriceEntry.SetPlaceHolder(fmt.Sprintf("%s/%s (high)", selectedPair.baseCurrency, w.accountCurrencySelect.Selected))
			w.baseLowPriceEntry.SetPlaceHolder(fmt.Sprintf("%s/%s (low)", selectedPair.baseCurrency, w.accountCurrencySelect.Selected))
			w.quoteHighPriceEntry.SetPlaceHolder(fmt.Sprintf("%s/%s (high)", selectedPair.quoteCurrency, w.accountCurrencySelect.Selected))
			w.quoteLowPriceEntry.SetPlaceHolder(fmt.Sprintf("%s/%s (low)", selectedPair.quoteCurrency, w.accountCurrencySelect.Selected))
		}
	}

	// Update on account currency change
	w.accountCurrencySelect.OnChanged = func(s string) {
		updatePriceInputs()
		w.riskLabel.SetText(fmt.Sprintf("Risk Amount (%s)", s))
	}

	// Update on instrument change
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

	// Create containers for base/quote currency inputs with corrected labels
	ui.baseContainer = container.NewVBox(
		widget.NewLabelWithStyle("Base/Home Price", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
		container.NewGridWithColumns(2,
			container.NewVBox(
				widget.NewLabelWithStyle("High", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				w.baseHighPriceEntry,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("Low", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				w.baseLowPriceEntry,
			),
		),
	)

	ui.quoteContainer = container.NewVBox(
		widget.NewLabelWithStyle("Quote/Home Price", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
		container.NewGridWithColumns(2,
			container.NewVBox(
				widget.NewLabelWithStyle("High", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				w.quoteHighPriceEntry,
			),
			container.NewVBox(
				widget.NewLabelWithStyle("Low", fyne.TextAlignLeading, fyne.TextStyle{Italic: true}),
				w.quoteLowPriceEntry,
			),
		),
	)

	// Trade parameters layout with base container first
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
		),
		ui.baseContainer,  // Base first
		ui.quoteContainer, // Quote second
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

	// Call updatePriceInputs after containers are created
	ui.setupCallbacks()
	ui.widgets.accountCurrencySelect.OnChanged(ui.widgets.accountCurrencySelect.Selected)

	// Evaluate initial state
	var selectedPair FXPair
	for _, pair := range ui.fxPairs {
		if pair.name == w.instrumentSelect.Selected {
			selectedPair = pair
			break
		}
	}

	// Show/hide containers based on initial state
	if selectedPair.quoteCurrency == w.accountCurrencySelect.Selected {
		ui.baseContainer.Show()
		ui.quoteContainer.Hide()
	} else if selectedPair.baseCurrency == w.accountCurrencySelect.Selected {
		ui.baseContainer.Hide()
		ui.quoteContainer.Show()
	} else {
		ui.baseContainer.Show()
		ui.quoteContainer.Show()
	}

	// Quote container is always shown
	ui.quoteContainer.Show()
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

	// Get selected pair
	var selectedPair FXPair
	for _, pair := range ui.fxPairs {
		if pair.name == w.instrumentSelect.Selected {
			selectedPair = pair
			break
		}
	}

	// Debug output
	fmt.Printf("Account Currency: %s\n", w.accountCurrencySelect.Selected)
	fmt.Printf("Base Currency: %s\n", selectedPair.baseCurrency)
	fmt.Printf("Quote Currency: %s\n", selectedPair.quoteCurrency)
	fmt.Printf("Quote High Price Text: '%s'\n", w.quoteHighPriceEntry.Text)
	fmt.Printf("Quote Low Price Text: '%s'\n", w.quoteLowPriceEntry.Text)

	// Parse price inputs based on which are active
	var baseHighPrice, baseLowPrice, quoteHighPrice, quoteLowPrice float64
	var err4, err5, err6, err7 error

	// Parse prices based on currency relationship
	if selectedPair.quoteCurrency == w.accountCurrencySelect.Selected {
		fmt.Println("Using quote=home currency logic")
		baseHighPrice, err4 = strconv.ParseFloat(w.baseHighPriceEntry.Text, 64)
		baseLowPrice, err5 = strconv.ParseFloat(w.baseLowPriceEntry.Text, 64)
		quoteHighPrice = 1.0
		quoteLowPrice = 1.0
		if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil {
			w.errorLabel.Text = "Please enter valid numbers"
			w.errorLabel.Refresh()
			hideResults()
			return
		}
	} else if selectedPair.baseCurrency == w.accountCurrencySelect.Selected {
		baseHighPrice = 1.0
		baseLowPrice = 1.0
		quoteHighPrice, err4 = strconv.ParseFloat(w.quoteHighPriceEntry.Text, 64)
		quoteLowPrice, err5 = strconv.ParseFloat(w.quoteLowPriceEntry.Text, 64)
		if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil {
			w.errorLabel.Text = "Please enter valid numbers"
			w.errorLabel.Refresh()
			hideResults()
			return
		}
	} else {
		baseHighPrice, err4 = strconv.ParseFloat(w.baseHighPriceEntry.Text, 64)
		baseLowPrice, err5 = strconv.ParseFloat(w.baseLowPriceEntry.Text, 64)
		quoteHighPrice, err6 = strconv.ParseFloat(w.quoteHighPriceEntry.Text, 64)
		quoteLowPrice, err7 = strconv.ParseFloat(w.quoteLowPriceEntry.Text, 64)
		if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil || err6 != nil || err7 != nil {
			w.errorLabel.Text = "Please enter valid numbers"
			w.errorLabel.Refresh()
			hideResults()
			return
		}
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
	if baseHighPrice <= 0 || baseLowPrice <= 0 || quoteHighPrice <= 0 || quoteLowPrice <= 0 {
		w.errorLabel.Text = "Prices must be positive"
		hideResults()
		return
	}
	if baseLowPrice > baseHighPrice || quoteLowPrice > quoteHighPrice {
		w.errorLabel.Text = "Low price cannot be higher than high price"
		hideResults()
		return
	}

	// Parse leverage
	leverageStr := strings.Split(w.leverageSelect.Selected, ":")[0]
	leverage, _ := strconv.ParseFloat(leverageStr, 64)

	// Calculate exchange rates for home currency conversion
	var homeBaseRateHigh, homeBaseRateLow, homeQuoteRateHigh, homeQuoteRateLow float64

	if selectedPair.baseCurrency == w.accountCurrencySelect.Selected {
		homeBaseRateHigh = 1.0
		homeBaseRateLow = 1.0
		homeQuoteRateHigh = quoteHighPrice
		homeQuoteRateLow = quoteLowPrice
	} else if selectedPair.quoteCurrency == w.accountCurrencySelect.Selected {
		homeBaseRateHigh = baseHighPrice
		homeBaseRateLow = baseLowPrice
		homeQuoteRateHigh = 1.0
		homeQuoteRateLow = 1.0
	} else {
		homeBaseRateHigh = baseHighPrice
		homeBaseRateLow = baseLowPrice
		homeQuoteRateHigh = quoteHighPrice
		homeQuoteRateLow = quoteLowPrice
	}

	// Debug logging
	fmt.Printf("High Price Calculation:\n")
	fmt.Printf("Base Price: %f\n", baseHighPrice)
	fmt.Printf("Home Base Rate: %f\n", homeBaseRateHigh)
	fmt.Printf("Home Quote Rate: %f\n", homeQuoteRateHigh)
	fmt.Printf("Leverage: %f\n", leverage)
	fmt.Printf("Available Margin: %f\n", availableMargin)

	// Calculate for high price
	highUnits, highPipValue, maxHighUnits, errMsg := trade.CalculatePositionDetails(
		availableMargin, leverage, riskAmount,
		baseHighPrice, stopLoss,
		homeBaseRateHigh, homeQuoteRateHigh,
		selectedPair.baseCurrency,
		selectedPair.quoteCurrency,
		w.accountCurrencySelect.Selected,
	)

	fmt.Printf("Max Units High: %d\n", maxHighUnits)

	if errMsg != "" {
		w.errorLabel.Text = errMsg
		w.errorLabel.Refresh()
		hideResults()
		return
	}

	// Calculate for low price
	lowUnits, lowPipValue, maxLowUnits, errMsg := trade.CalculatePositionDetails(
		availableMargin, leverage, riskAmount,
		baseLowPrice, stopLoss,
		homeBaseRateLow, homeQuoteRateLow,
		selectedPair.baseCurrency,
		selectedPair.quoteCurrency,
		w.accountCurrencySelect.Selected,
	)

	if errMsg != "" {
		w.errorLabel.Text = errMsg
		w.errorLabel.Refresh()
		hideResults()
		return
	}

	// Calculate average values
	avgUnits := (highUnits + lowUnits) / 2
	avgPipValue := (highPipValue + lowPipValue) / 2
	maxUnits := int((float64(maxHighUnits) + float64(maxLowUnits)) / 2.0)

	// Update max position label
	w.maxPositionLabel.SetText(fmt.Sprintf("Maximum Position: %d units", maxUnits))

	// Clear error message on successful calculation
	w.errorLabel.Text = ""
	w.errorLabel.Refresh()

	// Show all positions for different currencies
	w.highPositionLabel.Show()
	w.lowPositionLabel.Show()
	w.avgPositionLabel.Show()

	w.highPositionLabel.SetText(fmt.Sprintf("Position Size [High Price]: %d units", highUnits))
	w.avgPositionLabel.SetText(fmt.Sprintf("Position Size [Average Price]: %d units", avgUnits))
	w.lowPositionLabel.SetText(fmt.Sprintf("Position Size [Low Price]: %d units", lowUnits))

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
			showTradeDetails(avgUnits, avgPipValue, (baseHighPrice+baseLowPrice)/2, maxUnits)
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
			showTradeDetails(highUnits, highPipValue, baseHighPrice, int(maxHighUnits))
		}
		w.lowPositionLabel.OnTapped = func() {
			showTradeDetails(lowUnits, lowPipValue, baseLowPrice, int(maxLowUnits))
		}
		w.avgPositionLabel.OnTapped = func() {
			showTradeDetails(avgUnits, avgPipValue, (baseHighPrice+baseLowPrice)/2, maxUnits)
		}
	}

	// Update max position label and hide pip value
	w.maxPositionLabel.SetText(fmt.Sprintf("Maximum Position: %d units", maxUnits))
	w.pipValueLabel.Hide()
}
