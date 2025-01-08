package ui

// GetFXPairs returns the list of supported FX pairs
func GetFXPairs() []FXPair {
	return []FXPair{
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
}

// GetAccountCurrencies returns supported account currencies
func GetAccountCurrencies() []string {
	return []string{"USD", "EUR", "GBP", "JPY", "CHF", "AUD", "CAD", "NZD"}
}

// GetLeverageOptions returns available leverage options
func GetLeverageOptions() []string {
	return []string{
		"1:1", "2:1", "5:1", "10:1", "20:1", "50:1", "100:1", "500:1",
		"1000:1", "2000:1", "3000:1",
	}
}
