package trade

import (
	"strings"
)

// CalculatePositionDetails returns position size, pip value, max units, and error message
func CalculatePositionDetails(
	// Account parameters
	availableMargin,
	leverage,
	riskAmount,

	// Price parameters
	price,
	stopLossPips,
	homeRate,
	homeQuoteRate float64,

	// Currency parameters
	baseCurrency,
	quoteCurrency,
	homeCurrency string,
) (int, float64, int, string) {
	// Calculate pip value in quote currency
	pipValue := 0.0001
	if quoteCurrency == "JPY" || strings.HasSuffix(quoteCurrency, "JPY") {
		pipValue = 0.01
	} else if quoteCurrency == "XAU" {
		pipValue = 0.1
	}

	// Calculate stop loss in price terms
	stopLossDistance := stopLossPips * pipValue

	// Calculate position size based on risk
	riskInQuoteCurrency := riskAmount / homeQuoteRate
	positionSize := riskInQuoteCurrency / stopLossDistance

	// Calculate maximum position size based on remaining margin
	remainingMargin := availableMargin - riskAmount
	marginRate := 1 / leverage

	// Calculate margin requirement in account currency
	var marginRequirement float64
	if baseCurrency == homeCurrency {
		marginRequirement = price / homeQuoteRate
	} else if quoteCurrency == homeCurrency {
		marginRequirement = price
	} else {
		marginRequirement = price * homeRate
	}

	maxUnits := remainingMargin / (marginRate * marginRequirement)

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
