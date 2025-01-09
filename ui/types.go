package ui

import (
	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/widget"
)

// FXPair structure
type FXPair struct {
	name          string
	baseCurrency  string
	quoteCurrency string
}

// UI holds all the UI components and state
type UI struct {
	window         fyne.Window
	fxPairs        []FXPair
	widgets        *Widgets
	baseContainer  *fyne.Container
	quoteContainer *fyne.Container
}

// Widgets holds all the UI widgets
type Widgets struct {
	accountCurrencySelect  *widget.Select
	leverageSelect         *widget.Select
	availableMarginEntry   *widget.Entry
	instrumentSelect       *widget.Select
	riskAmountHomeCurrency *widget.Entry
	riskAmountPips         *widget.Entry
	highPriceEntry         *widget.Entry
	lowPriceEntry          *widget.Entry
	errorLabel             *canvas.Text

	// Result labels
	positionLabel     *widget.Hyperlink
	highPositionLabel *widget.Hyperlink
	lowPositionLabel  *widget.Hyperlink
	avgPositionLabel  *widget.Hyperlink
	maxPositionLabel  *widget.Label
	pipValueLabel     *widget.Label
	riskLabel         *widget.Label

	// Additional price inputs for cross rates
	baseHighPriceEntry  *widget.Entry
	baseLowPriceEntry   *widget.Entry
	quoteHighPriceEntry *widget.Entry
	quoteLowPriceEntry  *widget.Entry
}
