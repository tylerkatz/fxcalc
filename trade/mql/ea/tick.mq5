//+------------------------------------------------------------------+
//| Simple Risk-Based EA                                               |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

// Include required files
#include <Trade\Trade.mqh>

// Input parameters
input double   RiskAmount    = 100.0;      // Risk Amount in account currency
input double   StopLossPips  = 20.0;       // Stop Loss in pips (positive)
input double   TakeProfitPips= 40.0;       // Take Profit in pips (positive)
input bool     IsLongTrade   = true;       // Trade Direction (true=Long, false=Short)
input bool     IsTestMode    = true;       // Test Mode (true=Virtual trades, false=Real trades)

// Global variables
CTrade        trade;                        // Trading object
double        point;                        // Point value
int           symbolDigits;                 // Digits in price
double        pipValue;                     // Value of one pip
int           virtualTradeCount = 0;        // Counter for virtual trades
double          initialChartRange = 0;      // Store initial chart range
double          initialOffsetSize = 0;      // Store initial offset size

struct VirtualTrade {
    bool     isLong;
    double   entryPrice;
    double   stopLoss;
    double   takeProfit;
    double   visualEntry;    // Added for visual price storage
    double   visualSL;       // Added for visual price storage
    double   visualTP;       // Added for visual price storage
    double   lots;
    bool     isActive;
    double   initialTpDistance;  // Store initial TP distance
    double   initialSlDistance;  // Added to store initial SL distance
};
VirtualTrade currentVirtualTrade;

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validate inputs
    if(StopLossPips <= 0 || TakeProfitPips <= 0)
    {
        Print("Stop Loss and Take Profit must be positive values!");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Initialize trading object
    trade.SetExpertMagicNumber(123456);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    // Get symbol properties
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    pipValue = (symbolDigits == 3 || symbolDigits == 5) ? point * 10 : point;
    
    Print("Symbol Digits: ", symbolDigits, " Point: ", point, " Pip Value: ", pipValue);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Draw virtual trade on chart                                        |
//+------------------------------------------------------------------+
void DrawVirtualTrade(bool isLong, double entryPrice, double stopLoss, double takeProfit, double lots)
{
    // Only proceed if we don't already have an active trade AND virtualTradeCount is 0
    if(currentVirtualTrade.isActive || virtualTradeCount > 0) {
        Print("DEBUG - DrawVirtualTrade - Already active trade");
        return;
    }
    
    Print("DEBUG - DrawVirtualTrade - Starting new trade");
    
    // Calculate proper entry, SL and TP prices considering spread
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread = ask - bid;
    
    // Visual prices for drawing on chart (BID-based)
    double visualEntry, visualSL, visualTP;
    
    if(isLong)
    {
        // Long trade: Enter at ASK, SL/TP checked against BID
        visualEntry = bid + spread;  // Show entry at ASK by adding spread to BID
        visualSL = bid - (StopLossPips * pipValue);  // SL below entry, using BID
        visualTP = bid + (TakeProfitPips * pipValue);  // TP above entry, using BID
        
        // Store both visual and check prices
        currentVirtualTrade.entryPrice = ask;
        currentVirtualTrade.stopLoss = visualSL;
        currentVirtualTrade.takeProfit = visualTP;
        currentVirtualTrade.visualEntry = visualEntry;  // Show ASK by adding spread
        currentVirtualTrade.visualSL = visualSL;
        currentVirtualTrade.visualTP = visualTP;
        currentVirtualTrade.isLong = isLong;
        currentVirtualTrade.lots = lots;
        currentVirtualTrade.isActive = true;
        Print("DEBUG - Long trade activated");
        
        // For longs, we don't draw the ASK line
    }
    else
    {
        // Short trade: Enter at BID, check against ASK
        visualEntry = bid;  // Show entry at actual BID price
        visualSL = ask + (StopLossPips * pipValue);  // SL at ASK + input StopLossPips
        visualTP = bid - (TakeProfitPips * pipValue);  // TP at BID - input TakeProfitPips
        
        // Calculate actual check prices
        double slCheck = ask + (StopLossPips * pipValue);  
        double tpCheck = visualTP;  // For shorts, target ASK is same as visual TP (BID - pips)
        
        // Calculate actual distances
        double slDistance = StopLossPips;  // Distance to SL from ASK
        double tpDistance = MathAbs(ask - visualTP) / pipValue;  // Distance from entry ASK to target ASK
        
        // Detailed trade info
        Print("SHORT Trade Details:",
              "\nPrices:",
              "\n  BID: ", bid,
              "\n  ASK: ", ask,
              "\n  Spread: ", spread, " (", spread/pipValue, " pips)",
              "\nExecution Prices (ASK-based exits):",
              "\n  Entry ASK: ", ask,
              "\n  SL: ", slCheck, " (ASK+", slDistance, " pips)",
              "\n  TP ASK: ", tpCheck, " (BID-", TakeProfitPips, " pips)",
              "\nVisual Prices (BID-based for chart):",
              "\n  Entry: ", visualEntry,
              "\n  SL: ", visualSL, " (+", slDistance, " pips from ASK)",
              "\n  TP: ", visualTP, " (-", TakeProfitPips, " pips from BID)",
              "\nActual Distances:",
              "\n  Entry to SL: ", slDistance, " pips",
              "\n  Entry ASK to TP ASK: ", tpDistance, " pips");
              
        // Summary trade info using actual distances
        Print("Virtual SELL trade placed: Lots=", lots, 
              ", Entry=", visualEntry, 
              ", SL=", visualSL, " (", tpDistance, " pips)", 
              ", TP=", visualTP, " (", tpDistance, " pips)");
        
        // Store both visual and check prices
        currentVirtualTrade.entryPrice = bid;
        currentVirtualTrade.stopLoss = slCheck;
        currentVirtualTrade.takeProfit = tpCheck;
        currentVirtualTrade.visualEntry = visualEntry;
        currentVirtualTrade.visualSL = visualSL;
        currentVirtualTrade.visualTP = visualTP;
        currentVirtualTrade.isLong = false;
        currentVirtualTrade.isActive = true;
        Print("DEBUG - Short trade activated");
        
        // Draw ASK line with price label - using TP color for shorts
        string prefix = "VirtualTrade_" + IntegerToString(virtualTradeCount);
        string askLineName = prefix + "_ASK";
        ObjectCreate(0, askLineName, OBJ_HLINE, 0, 0, ask);
        ObjectSetInteger(0, askLineName, OBJPROP_COLOR, C'0,33,165');  // Changed to TP blue color
        ObjectSetInteger(0, askLineName, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, askLineName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, askLineName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, askLineName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, askLineName, OBJPROP_BACK, true);
        
        // Add price label to ASK line
        string askPriceName = prefix + "_ASK_Price";
        datetime currentTime = TimeCurrent();
        datetime timeOffsetRight = currentTime + (PeriodSeconds() * 11);
        
        // Calculate offset based on chart's visible price range
        double upperPrice = ChartGetDouble(0, CHART_PRICE_MAX);
        double lowerPrice = ChartGetDouble(0, CHART_PRICE_MIN);
        double priceRange = upperPrice - lowerPrice;
        double verticalOffset = priceRange * 0.015;  // 1.5% of visible price range
        
        ObjectCreate(0, askPriceName, OBJ_TEXT, 0, timeOffsetRight, ask - verticalOffset);
        ObjectSetString(0, askPriceName, OBJPROP_TEXT, StringFormat("ASK: %f", ask));
        ObjectSetInteger(0, askPriceName, OBJPROP_COLOR, C'0,33,165');  // Changed to TP blue color
        ObjectSetInteger(0, askPriceName, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetInteger(0, askPriceName, OBJPROP_BACK, false);
        ObjectSetInteger(0, askPriceName, OBJPROP_FONTSIZE, 7);
    }
    
    // Draw using visual prices
    string prefix = "VirtualTrade_" + IntegerToString(virtualTradeCount);
    
    // Draw entry line
    string entryName = prefix + "_Entry";
    ObjectCreate(0, entryName, OBJ_HLINE, 0, 0, visualEntry);
    ObjectSetInteger(0, entryName, OBJPROP_COLOR, C'0,33,165');
    ObjectSetInteger(0, entryName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, entryName, OBJPROP_SELECTABLE, false);  // Prevent selection
    ObjectSetInteger(0, entryName, OBJPROP_SELECTED, false);    // Prevent selection
    ObjectSetInteger(0, entryName, OBJPROP_BACK, true);        // Put line in background
    
    // Draw SL line
    string slName = prefix + "_SL";
    ObjectCreate(0, slName, OBJ_HLINE, 0, 0, visualSL);
    ObjectSetInteger(0, slName, OBJPROP_COLOR, C'250,70,22');
    ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, slName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, slName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, slName, OBJPROP_BACK, true);
    
    // Draw TP line
    string tpName = prefix + "_TP";
    ObjectCreate(0, tpName, OBJ_HLINE, 0, 0, visualTP);
    ObjectSetInteger(0, tpName, OBJPROP_COLOR, C'0,33,165');
    ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, tpName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, tpName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, tpName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, tpName, OBJPROP_BACK, true);
    
    // Calculate arrow height in price units
    int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    double pricePerPixel = (ChartGetDouble(0, CHART_PRICE_MAX) - ChartGetDouble(0, CHART_PRICE_MIN)) / chartHeight;
    double arrowHeight = pricePerPixel * 28;
    double textOffset = pricePerPixel * 28;
    
    // Calculate time offset for text (4 bars ahead instead of 2)
    datetime currentTime = TimeCurrent();
    datetime timeOffset = currentTime + (PeriodSeconds() * 4);  // Changed from 2 to 4
    
    // Add SL pip distance text - position ABOVE the SL line
    string slPipText = prefix + "_SL_Pips";
    double slPips = StopLossPips;  // Use input value
    double initialSlDistance = currentVirtualTrade.isLong ? 
                             -(StopLossPips) :  // For longs: just negative SL pips
                             -(MathAbs(visualSL - visualEntry) / pipValue);  // For shorts: -(SL price - entry price)
    currentVirtualTrade.initialSlDistance = initialSlDistance;  // Store the initial distance
    
    ObjectCreate(0, slPipText, OBJ_TEXT, 0, timeOffset, visualSL + textOffset);
    ObjectSetString(0, slPipText, OBJPROP_TEXT, StringFormat("%.1f pips (%.1f pips)", 
                   slPips, currentVirtualTrade.initialSlDistance));
    ObjectSetInteger(0, slPipText, OBJPROP_COLOR, C'250,70,22');  // Custom orange
    ObjectSetInteger(0, slPipText, OBJPROP_ANCHOR, ANCHOR_LEFT);
    
    // Add TP pip distance text - position BELOW the TP line
    string tpPipText = prefix + "_TP_Pips";
    double initialTpDistance = currentVirtualTrade.isLong ? 
                              MathAbs(visualTP - bid) / pipValue :
                              MathAbs(ask - visualTP) / pipValue;  // For shorts: entry ASK to target ASK
    currentVirtualTrade.initialTpDistance = initialTpDistance;  // Store the initial distance
    
    ObjectCreate(0, tpPipText, OBJ_TEXT, 0, timeOffset, visualTP - textOffset);
    ObjectSetString(0, tpPipText, OBJPROP_TEXT, StringFormat("%.1f pips (+%.1f pips)", 
                   currentVirtualTrade.initialTpDistance, TakeProfitPips));
    ObjectSetInteger(0, tpPipText, OBJPROP_COLOR, C'0,33,165');  // Custom blue
    ObjectSetInteger(0, tpPipText, OBJPROP_ANCHOR, ANCHOR_LEFT);
    
    // Add entry arrow
    string arrowName = prefix + "_EntryArrow";
    double arrowPrice = visualEntry;
    if(!isLong) // For short trades, offset by exact arrow height
        arrowPrice = visualEntry + arrowHeight;
        
    ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), arrowPrice);
    ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isLong ? 233 : 234);  // Up arrow for long, Down arrow for short
    ObjectSetInteger(0, arrowName, OBJPROP_COLOR, C'0,33,165');  // Blue
    ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, isLong ? ANCHOR_BOTTOM : ANCHOR_TOP);
    ObjectSetInteger(0, arrowName, (ENUM_OBJECT_PROPERTY_INTEGER)OBJPROP_SCALE, (long)60);
    
    // Add text label with trade details
    string labelName = prefix + "_Label";
    string direction = isLong ? "BUY" : "SELL";
    string label = StringFormat("%s: %.2f lots\nEntry: %f\nSL: %f (%0.1f pips)\nTP: %f (%0.1f pips)", 
                               direction, lots, visualEntry, visualSL, slPips, visualTP, initialTpDistance);
    ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(0, labelName, OBJPROP_TEXT, label);
    ObjectSetInteger(0, labelName, OBJPROP_COLOR, C'0,33,165');
    ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 20 + (virtualTradeCount * 100));
    
    virtualTradeCount++;
    Print("DEBUG - Trade creation complete - isActive: ", currentVirtualTrade.isActive);
}

//+------------------------------------------------------------------+
//| Check if virtual trade hit SL or TP                                |
//+------------------------------------------------------------------+
void CheckVirtualTrade()
{
    if(!currentVirtualTrade.isActive) {
        Print("DEBUG - Trade not active");
        return;
    }
        
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Debug logging every tick for shorts
    if(!currentVirtualTrade.isLong) {
        Print("DEBUG - Short Trade Check:");
        Print("ASK: ", ask);
        Print("SL Level: ", currentVirtualTrade.stopLoss);
        Print("TP Level: ", currentVirtualTrade.takeProfit);
        Print("Is Active: ", currentVirtualTrade.isActive);
        Print("ASK >= SL?: ", (ask >= currentVirtualTrade.stopLoss));
        Print("Difference: ", ask - currentVirtualTrade.stopLoss, " points");
        Print("isLong: ", currentVirtualTrade.isLong);
        
        // Add explicit comparison with full precision
        if(ask >= currentVirtualTrade.stopLoss) {
            Print("SL CHECK TRIGGERED!");
            Print("ASK: ", DoubleToString(ask, 8));
            Print("SL:  ", DoubleToString(currentVirtualTrade.stopLoss, 8));
        }
    }
    
    // Only log every 30 seconds using static variable
    static datetime lastLogTime = 0;
    datetime currentTime = TimeCurrent();
    
    if(currentTime >= lastLogTime + 30) {
        Print("Trade Status:");
        Print("Current ASK: ", ask);
        Print("Current BID: ", bid);
        Print("TP Level: ", currentVirtualTrade.takeProfit);
        Print("SL Level: ", currentVirtualTrade.stopLoss);
        lastLogTime = currentTime;
    }
    
    if(!currentVirtualTrade.isLong)  // Short position
    {
        if(ask >= currentVirtualTrade.stopLoss)
        {
            Print("SL HIT! ASK(", ask, ") >= SL(", currentVirtualTrade.stopLoss, ")");
            Print("TRADE EXIT - Stop Loss");
            Print("Entry: ", currentVirtualTrade.entryPrice);
            Print("Exit: ", ask);
            Print("Loss: ", (ask - currentVirtualTrade.entryPrice) / pipValue, " pips");
            
            // Create exit X at ASK level
            string prefix = "VirtualTrade_" + IntegerToString(virtualTradeCount-1);
            ObjectCreate(0, prefix + "_Exit", OBJ_ARROW_STOP, 0, TimeCurrent(), ask);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_SELECTABLE, false);
            
            // Clear trade but keep entry arrow and exit symbol
            currentVirtualTrade.isActive = false;
            DeleteVirtualTradeObjectsExceptArrows();
            Sleep(5000);
            return;
        }
        if(ask <= currentVirtualTrade.takeProfit)
        {
            Print("TP HIT! ASK(", ask, ") <= TP(", currentVirtualTrade.takeProfit, ")");
            Print("TRADE EXIT - Take Profit");
            Print("Entry: ", currentVirtualTrade.entryPrice);
            Print("Exit: ", ask);
            Print("Profit: ", (currentVirtualTrade.entryPrice - ask) / pipValue, " pips");
            
            // Create checkmark at ASK level
            string prefix = "VirtualTrade_" + IntegerToString(virtualTradeCount-1);
            ObjectCreate(0, prefix + "_Exit", OBJ_ARROW_CHECK, 0, TimeCurrent(), ask);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_SELECTABLE, false);
            
            // Clear trade but keep entry arrow and exit symbol
            currentVirtualTrade.isActive = false;
            DeleteVirtualTradeObjectsExceptArrows();
            Sleep(5000);
            return;
        }
    }
    else  // Long position
    {
        if(bid <= currentVirtualTrade.stopLoss)
        {
            Print("SL HIT! BID(", bid, ") <= SL(", currentVirtualTrade.stopLoss, ")");
            Print("TRADE EXIT - Stop Loss");
            Print("Entry: ", currentVirtualTrade.entryPrice);
            Print("Exit: ", bid);
            Print("Loss: ", (currentVirtualTrade.entryPrice - bid) / pipValue, " pips");
            
            // Create exit X at ASK level
            string prefix = "VirtualTrade_" + IntegerToString(virtualTradeCount-1);
            ObjectCreate(0, prefix + "_Exit", OBJ_ARROW_STOP, 0, TimeCurrent(), bid);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_SELECTABLE, false);
            
            currentVirtualTrade.isActive = false;
            DeleteVirtualTradeObjectsExceptArrows();
            Sleep(5000);
            return;
        }
        if(bid >= currentVirtualTrade.takeProfit)
        {
            Print("TP HIT! BID(", bid, ") >= TP(", currentVirtualTrade.takeProfit, ")");
            Print("TRADE EXIT - Take Profit");
            Print("Entry: ", currentVirtualTrade.entryPrice);
            Print("Exit: ", bid);
            Print("Profit: ", (bid - currentVirtualTrade.entryPrice) / pipValue, " pips");
            
            // Create checkmark at ASK level
            string prefix = "VirtualTrade_" + IntegerToString(virtualTradeCount-1);
            ObjectCreate(0, prefix + "_Exit", OBJ_ARROW_CHECK, 0, TimeCurrent(), bid);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, prefix + "_Exit", OBJPROP_SELECTABLE, false);
            
            currentVirtualTrade.isActive = false;
            DeleteVirtualTradeObjectsExceptArrows();
            Sleep(5000);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Delete all virtual trade objects except arrows                     |
//+------------------------------------------------------------------+
void DeleteVirtualTradeObjectsExceptArrows()
{
    string prefix = "VirtualTrade_" + IntegerToString(virtualTradeCount-1);
    ObjectDelete(0, prefix + "_SL");
    ObjectDelete(0, prefix + "_TP");
    ObjectDelete(0, prefix + "_Label");
    ObjectDelete(0, prefix + "_SL_Pips");
    ObjectDelete(0, prefix + "_TP_Pips");
    ObjectDelete(0, prefix + "_ASK");
    ObjectDelete(0, prefix + "_ASK_Price");
    
    // Note: NOT deleting:
    // prefix + "_EntryArrow"
    // prefix + "_Exit"
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                              |
//+------------------------------------------------------------------+
double CalculatePositionSize(double riskAmount, double stopLossPips)
{
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    // Calculate pip value in account currency
    double pipValueInCurrency = (tickValue * pipValue) / tickSize;
    
    // Calculate required position size
    double positionSize = riskAmount / (stopLossPips * pipValueInCurrency);
    
    // Round to nearest lot step
    positionSize = MathFloor(positionSize / lotStep) * lotStep;
    
    // Ensure position size is within allowed limits
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    // First check if existing virtual trade hit any levels
    if(IsTestMode) {
        Print("DEBUG - OnTick - Before CheckVirtualTrade - isActive: ", currentVirtualTrade.isActive);
        CheckVirtualTrade();
        Print("DEBUG - OnTick - After CheckVirtualTrade - isActive: ", currentVirtualTrade.isActive);
    }
    
    // Update ASK line and price if we have an active short virtual trade
    if(IsTestMode && virtualTradeCount > 0 && !currentVirtualTrade.isLong)
    {
        string prefix = "VirtualTrade_0";  // First virtual trade
        string askLineName = prefix + "_ASK";
        string askPriceName = prefix + "_ASK_Price";
        string slPipText = prefix + "_SL_Pips";
        string tpPipText = prefix + "_TP_Pips";
        double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // Update ASK line with same properties - using TP blue color
        ObjectSetDouble(0, askLineName, OBJPROP_PRICE, currentAsk);
        ObjectSetInteger(0, askLineName, OBJPROP_COLOR, C'0,33,165');  // Changed to TP blue color
        ObjectSetInteger(0, askLineName, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, askLineName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, askLineName, OBJPROP_BACK, true);
        
        // Update ASK price label with same properties
        datetime currentTime = TimeCurrent();
        datetime timeOffsetRight = currentTime + (PeriodSeconds() * 11);
        
        // Calculate offset based on chart's visible price range
        double upperPrice = ChartGetDouble(0, CHART_PRICE_MAX);
        double lowerPrice = ChartGetDouble(0, CHART_PRICE_MIN);
        double priceRange = upperPrice - lowerPrice;
        double verticalOffset = priceRange * 0.015;  // 1.5% of visible price range
        
        ObjectSetDouble(0, askPriceName, OBJPROP_PRICE, currentAsk - verticalOffset);
        ObjectSetString(0, askPriceName, OBJPROP_TEXT, StringFormat("ASK: %f", currentAsk));
        ObjectSetInteger(0, askPriceName, OBJPROP_TIME, timeOffsetRight);
        ObjectSetInteger(0, askPriceName, OBJPROP_COLOR, C'0,33,165');  // Changed to TP blue color
        ObjectSetInteger(0, askPriceName, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetInteger(0, askPriceName, OBJPROP_BACK, false);
        ObjectSetInteger(0, askPriceName, OBJPROP_FONTSIZE, 7);
        
        // Use stored values for distances
        ObjectSetString(0, slPipText, OBJPROP_TEXT, StringFormat("%.1f pips (%.1f pips)", 
                       StopLossPips, currentVirtualTrade.initialSlDistance));
        ObjectSetString(0, tpPipText, OBJPROP_TEXT, StringFormat("%.1f pips (+%.1f pips)", 
                       currentVirtualTrade.initialTpDistance, TakeProfitPips));
        
        return;
    }
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate stop loss and take profit levels based on direction
    double stopLoss, takeProfit;
    double lotSize = CalculatePositionSize(RiskAmount, StopLossPips);
    
    if(IsLongTrade)
    {
        stopLoss = bid - (StopLossPips * pipValue);
        takeProfit = ask + (TakeProfitPips * pipValue);
        if(IsTestMode)
            DrawVirtualTrade(true, ask, stopLoss, takeProfit, lotSize);
        else
            trade.Buy(lotSize, _Symbol, ask, stopLoss, takeProfit, "Risk-based EA Long");
    }
    else
    {
        stopLoss = bid + (StopLossPips * pipValue);
        takeProfit = bid - (TakeProfitPips * pipValue);
        if(IsTestMode)
            DrawVirtualTrade(false, bid, stopLoss, takeProfit, lotSize);
        else
            trade.Sell(lotSize, _Symbol, bid, stopLoss, takeProfit, "Risk-based EA Short");
    }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up all virtual trade objects including arrows and ASK line
    for(int i=0; i<virtualTradeCount; i++)
    {
        string prefix = "VirtualTrade_" + IntegerToString(i);
        ObjectDelete(0, prefix + "_Entry");
        ObjectDelete(0, prefix + "_SL");
        ObjectDelete(0, prefix + "_TP");
        ObjectDelete(0, prefix + "_Label");
        ObjectDelete(0, prefix + "_SL_Pips");
        ObjectDelete(0, prefix + "_TP_Pips");
        ObjectDelete(0, prefix + "_EntryArrow");
        ObjectDelete(0, prefix + "_ExitArrow");
        ObjectDelete(0, prefix + "_ASK");
        ObjectDelete(0, prefix + "_ASK_Price");  // Clean up ASK price label
    }
}
