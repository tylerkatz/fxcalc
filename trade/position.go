package trade

// CalculatePositionDetails returns position size, pip value, max units, and error message
func CalculatePositionDetails(
	// Account parameters
	availableMargin,
	leverage,
	riskAmount,

	// Price parameters
	basePrice,
	stopLossPips,
	homeQuoteRate float64,

	// Currency parameters
	quoteCurrency,
	homeCurrency string,
) (int, float64, int, string) {
	// Calculate pip value in quote currency
	pipValue := 0.0001
	if quoteCurrency == "JPY" {
		pipValue = 0.01
	} else if quoteCurrency == "XAU" {
		pipValue = 0.1
	}

	// Calculate stop loss in price terms
	stopLossDistance := stopLossPips * pipValue

	// Calculate position size based on risk
	positionSize := riskAmount / (stopLossDistance * homeQuoteRate)

	// Calculate maximum position size based on remaining margin
	remainingMargin := availableMargin - riskAmount
	marginRate := 1 / leverage
	var baseToHomeRate float64
	if quoteCurrency == homeCurrency {
		baseToHomeRate = basePrice
	} else {
		baseToHomeRate = basePrice * homeQuoteRate
	}
	maxUnits := remainingMargin / (marginRate * baseToHomeRate)

	// Check if we can achieve the desired risk
	actualPipValue := (pipValue * float64(int(positionSize)) * homeQuoteRate)
	actualRisk := actualPipValue * stopLossPips

	if actualRisk < riskAmount*0.99 { // Allow 1% tolerance
		return 0, 0, int(maxUnits), "Insufficient margin - reduce margin risk or increase stop loss PIPs"
	}

	// Check if position exceeds max units
	if positionSize > maxUnits {
		return 0, 0, int(maxUnits), "Insufficient margin - reduce margin risk or increase stop loss PIPs"
	}

	// Calculate pip value for the position
	pipValueInHomeCurrency := (pipValue * float64(int(positionSize)) * homeQuoteRate)

	return int(positionSize), pipValueInHomeCurrency, int(maxUnits), ""
}
