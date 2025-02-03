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
input double   Channel       = 10.0;       // Channel size in pips (negative for short)
input double   Level1Volume  = 0.1;        // Level 1 volume in lots
input double   Level1SL      = 20.0;       // Level 1 Stop Loss in pips
input double   Level1TP      = 40.0;        // Level 1 Take Profit in pips
input double   Level2Volume  = 0.2;         // Level 2 volume in lots
input double   Level2SL      = 20.0;        // Level 2 Stop Loss in pips
input double   Level2TP      = 40.0;         // Level 2 Take Profit in pips
input double   Level3Volume  = 0.3;          // Level 3 volume in lots
input double   Level3SL      = 20.0;         // Level 3 Stop Loss in pips
input double   Level3TP      = 40.0;          // Level 3 Take Profit in pips
input double   Level4Volume  = 0.4;           // Level 4 volume in lots
input double   Level4SL      = 20.0;            // Level 4 Stop Loss in pips
input double   Level4TP      = 40.0;            // Level 4 Take Profit in pips
input double   Level5Volume  = 0.5;             // Level 5 volume in lots
input double   Level5SL      = 20.0;              // Level 5 Stop Loss in pips
input double   Level5TP      = 40.0;              // Level 5 Take Profit in pips

// Global variables
CTrade        trade;                        // Trading object
double        point;                        // Point value
int           symbolDigits;                 // Digits in price
double        pipValue;                     // Value of one pip
double        initialChartRange = 0;        // Store initial chart range
double        initialOffsetSize = 0;        // Store initial offset size
bool          hasHitTakeProfit = false;     // Flag to track if any level has hit TP
bool          maxLevelReached = false;      // Flag to track if max level is reached

struct HedgeLevel {
    ulong ticket;         // Order ticket
    ulong positionTicket; // Position ticket (when order is triggered)
    bool isLong;         // Direction
    double entryPrice;   // Entry price
    double stopLoss;     // Stop loss price
    double takeProfit;   // Take profit price
    double volume;       // Volume in lots
    bool isActive;       // Whether this level is active
    datetime exitTime;   // Time when the level exited (0 if not exited)
    double exitPrice;    // Price at which the level exited
    bool statusChanged;  // Track status changes
};

HedgeLevel hedgeLevels[5];  // Array to store up to 5 hedge levels
bool isInitialTradeOpen = false;

// Add timer to control visualization updates
static datetime lastVisualizationUpdate = 0;
const int VISUALIZATION_UPDATE_INTERVAL = 5; // Seconds

// Define level colors at the top with other global variables
color levelColors[5] = {
    clrOrange,        // Level 1 - Orange
    clrDodgerBlue,    // Level 2 - Light Blue
    clrGold,          // Level 3 - Yellow/Gold
    clrAquamarine,    // Level 4 - Light Green
    clrMagenta        // Level 5 - Purple
};

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit()
{
    // Reset the TP flag on initialization
    hasHitTakeProfit = false;
    
    trade.SetExpertMagicNumber(123456);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    pipValue = (symbolDigits == 3 || symbolDigits == 5) ? point * 10 : point;
    
    return(INIT_SUCCEEDED);
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
//| Calculate profit/loss in dollars                                   |
//+------------------------------------------------------------------+
double CalculateDollarValue(double price, double entryPrice, bool isLong, double volume)
{
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    double priceDiff = isLong ? price - entryPrice : entryPrice - price;
    double points = priceDiff / tickSize;
    return points * tickValue * volume;
}

//+------------------------------------------------------------------+
//| Update price labels for a specific level                           |
//+------------------------------------------------------------------+
void UpdatePriceLabels(int level)
{
    if(!hedgeLevels[level].isActive && hedgeLevels[level].ticket == 0 && hedgeLevels[level].exitTime == 0) return;
    
    string basePrefix = "Level_" + IntegerToString(level+1);
    string slLabelName = basePrefix + "_SL_Label";
    string tpLabelName = basePrefix + "_TP_Label";
    string levelSuffix = " (L" + IntegerToString(level+1) + ")";
    
    // If level has exited, ensure label stays at exit point
    if(hedgeLevels[level].exitTime > 0 && hedgeLevels[level].isActive) {
        double exitDollarValue = CalculateDollarValue(hedgeLevels[level].exitPrice, 
                                                    hedgeLevels[level].entryPrice,
                                                    hedgeLevels[level].isLong,
                                                    hedgeLevels[level].volume);
                                                  
        // Create or update exit label at exit point
        string labelName = basePrefix + (hedgeLevels[level].exitPrice == hedgeLevels[level].stopLoss ? "_SL_Label" : "_TP_Label");
        color labelColor = hedgeLevels[level].exitPrice == hedgeLevels[level].stopLoss ? clrRed : clrGreen;
        
        if(ObjectFind(0, labelName) >= 0) {
            ObjectSetInteger(0, labelName, OBJPROP_TIME, hedgeLevels[level].exitTime);
            ObjectSetDouble(0, labelName, OBJPROP_PRICE, hedgeLevels[level].exitPrice);
            ObjectSetString(0, labelName, OBJPROP_TEXT, StringFormat("$%.2f%s", exitDollarValue, levelSuffix));
        } else {
            ObjectCreate(0, labelName, OBJ_TEXT, 0, hedgeLevels[level].exitTime, hedgeLevels[level].exitPrice);
            ObjectSetString(0, labelName, OBJPROP_TEXT, StringFormat("$%.2f%s", exitDollarValue, levelSuffix));
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, labelColor);
            ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
        }
        
        // Delete the other label
        ObjectDelete(0, basePrefix + (hedgeLevels[level].exitPrice == hedgeLevels[level].stopLoss ? "_TP_Label" : "_SL_Label"));
        return;
    }
    
    // Normal label updates for active or pending levels
    double slDollarValue = CalculateDollarValue(hedgeLevels[level].stopLoss, 
                                              hedgeLevels[level].entryPrice,
                                              hedgeLevels[level].isLong,
                                              hedgeLevels[level].volume);
                                              
    double tpDollarValue = CalculateDollarValue(hedgeLevels[level].takeProfit,
                                              hedgeLevels[level].entryPrice,
                                              hedgeLevels[level].isLong,
                                              hedgeLevels[level].volume);
    
    // Calculate label time position (2 candles into the future)
    datetime currentTime = TimeCurrent();
    datetime labelTime = currentTime + (PeriodSeconds(PERIOD_CURRENT) * 2);
    
    // Update active level labels
    if(ObjectFind(0, slLabelName) >= 0) {
        ObjectSetInteger(0, slLabelName, OBJPROP_TIME, labelTime);
        ObjectSetDouble(0, slLabelName, OBJPROP_PRICE, hedgeLevels[level].stopLoss);
        ObjectSetString(0, slLabelName, OBJPROP_TEXT, StringFormat("$%.2f%s", slDollarValue, levelSuffix));
    } else {
        ObjectCreate(0, slLabelName, OBJ_TEXT, 0, labelTime, hedgeLevels[level].stopLoss);
        ObjectSetString(0, slLabelName, OBJPROP_TEXT, StringFormat("$%.2f%s", slDollarValue, levelSuffix));
        ObjectSetInteger(0, slLabelName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, slLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetInteger(0, slLabelName, OBJPROP_FONTSIZE, 8);
    }
    
    if(ObjectFind(0, tpLabelName) >= 0) {
        ObjectSetInteger(0, tpLabelName, OBJPROP_TIME, labelTime);
        ObjectSetDouble(0, tpLabelName, OBJPROP_PRICE, hedgeLevels[level].takeProfit);
        ObjectSetString(0, tpLabelName, OBJPROP_TEXT, StringFormat("$%.2f%s", tpDollarValue, levelSuffix));
    } else {
        ObjectCreate(0, tpLabelName, OBJ_TEXT, 0, labelTime, hedgeLevels[level].takeProfit);
        ObjectSetString(0, tpLabelName, OBJPROP_TEXT, StringFormat("$%.2f%s", tpDollarValue, levelSuffix));
        ObjectSetInteger(0, tpLabelName, OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, tpLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetInteger(0, tpLabelName, OBJPROP_FONTSIZE, 8);
    }
}

//+------------------------------------------------------------------+
//| Update price labels when lines are moved                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
    // Update labels when chart period changes
    if(id == CHARTEVENT_CHART_CHANGE) {
        for(int i=0; i<5; i++) {
            UpdatePriceLabels(i);
        }
    }
    
    // Check if object was moved
    if(id == CHARTEVENT_OBJECT_DRAG) {
        // Find highest active level
        int highestActiveLevel = -1;
        for(int i=4; i>=0; i--) {
            if(hedgeLevels[i].isActive) {
                highestActiveLevel = i;
                break;
            }
        }
        
        // Only process next pending level
        int nextLevel = highestActiveLevel + 1;
        if(nextLevel >= 5) return;
        
        string basePrefix = "Level_" + IntegerToString(nextLevel+1);
        string entryName = basePrefix + "_Entry";
        string slName = basePrefix + "_SL";
        string tpName = basePrefix + "_TP";
        string slLabelName = basePrefix + "_SL_Label";
        string tpLabelName = basePrefix + "_TP_Label";
        
        // If one of our lines was moved
        if(sparam == slName || sparam == tpName) {
            double newPrice = ObjectGetDouble(0, sparam, OBJPROP_PRICE);
            double dollarValue = CalculateDollarValue(newPrice, 
                                                    hedgeLevels[nextLevel].entryPrice,
                                                    hedgeLevels[nextLevel].isLong,
                                                    hedgeLevels[nextLevel].volume);
                                                    
            // Update label position and text
            string labelName = (sparam == slName) ? slLabelName : tpLabelName;
            datetime currentTime = TimeCurrent();
            datetime labelTime = currentTime + (PeriodSeconds() * 2);
            
            ObjectCreate(0, labelName, OBJ_TEXT, 0, labelTime, newPrice);
            ObjectSetString(0, labelName, OBJPROP_TEXT, 
                          StringFormat("$%.2f", dollarValue));
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, 
                           (sparam == slName) ? clrRed : clrGreen);
            ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
            
            // Update the stored SL/TP values
            if(sparam == slName) {
                hedgeLevels[nextLevel].stopLoss = newPrice;
            } else {
                hedgeLevels[nextLevel].takeProfit = newPrice;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    // Only check for initial trade setup and exit conditions
    if(!isInitialTradeOpen && !maxLevelReached) {
        OpenInitialTrade();
        return;
    }
    
    // Check for exit conditions
    CheckExitConditions();
}

//+------------------------------------------------------------------+
//| Draw a horizontal line with given properties                       |
//+------------------------------------------------------------------+
void DrawLine(string name, double price, color lineColor)
{
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
//| Process trading logic                                              |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
   // Find highest active level
   int highestActiveLevel = -1;
   for(int i=4; i>=0; i--) {
       if(hedgeLevels[i].isActive) {
           highestActiveLevel = i;
           break;
       }
   }
   
   // Check each level's orders
   for(int i=0; i<=highestActiveLevel+1 && i<5; i++) {
       if(hedgeLevels[i].ticket > 0) {
           // Check if order is still open
           if(OrderSelect(hedgeLevels[i].ticket)) {
               // If pending order
               if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP || 
                  OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) {
                   // Check if triggered
                   if(!hedgeLevels[i].isActive) {
                       // Update status if order was triggered
                       if(PositionSelectByTicket(hedgeLevels[i].ticket)) {
                           hedgeLevels[i].isActive = true;
                           
                           // Place next level's pending order
                           if(i < 4) {  // Don't place after level 5
                               PlacePendingOrder(i + 1, !hedgeLevels[i].isLong, hedgeLevels[0].entryPrice);
                           }
                       }
                   }
               }
           }
           
           // Check for TP/SL hits
           if(hedgeLevels[i].isActive) {
               CheckLevelExit(i);
           }
       }
   }
}

void UpdateVisualization()
{
    // Calculate base prices
    double baseEntry = hedgeLevels[0].entryPrice;
    double channelEntry = baseEntry - MathAbs(Channel) * pipValue;
    
    // Draw channel borders
    DrawLine("Channel_Upper", baseEntry, clrGray, STYLE_SOLID, 1);
    DrawLine("Channel_Lower", channelEntry, clrGray, STYLE_SOLID, 1);
    
    // Draw levels
    for(int i=0; i<5; i++) {
        string prefix = "Level_" + IntegerToString(i+1);
        color levelColor = levelColors[i];
        
        // Draw if level has a ticket or is active and hasn't exited
        if((hedgeLevels[i].ticket > 0 || hedgeLevels[i].isActive) && hedgeLevels[i].exitTime == 0) {
            // Draw entry line
            DrawLine(prefix + "_Entry", hedgeLevels[i].entryPrice, levelColor, STYLE_SOLID, 2);
            
            // Draw SL/TP lines
            DrawLine(prefix + "_SL", hedgeLevels[i].stopLoss, levelColor, STYLE_DOT, 1);
            DrawLine(prefix + "_TP", hedgeLevels[i].takeProfit, levelColor, STYLE_DASH, 1);
        }
        else {
            ObjectDelete(0, prefix + "_Entry");
            ObjectDelete(0, prefix + "_SL");
            ObjectDelete(0, prefix + "_TP");
        }
    }
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helper function to draw lines                                      |
//+------------------------------------------------------------------+
void DrawLine(string name, double price, color clr, ENUM_LINE_STYLE style = STYLE_SOLID, int width = 1)
{
    if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) {
        ObjectMove(0, name, 0, 0, price);
    }
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
}

//+------------------------------------------------------------------+
//| Open initial trade                                                |
//+------------------------------------------------------------------+
void OpenInitialTrade()
{
    Print("Starting OpenInitialTrade");
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool isLong = Channel >= 0;
    
    // Place initial market order (Level 1)
    double entryPrice = isLong ? ask : bid;
    double sl = isLong ? entryPrice - Level1SL * pipValue : entryPrice + Level1SL * pipValue;
    double tp = isLong ? entryPrice + Level1TP * pipValue : entryPrice - Level1TP * pipValue;
    
    Print("Attempting Level 1 order: Direction=", isLong ? "Long" : "Short", 
          ", Entry=", entryPrice,
          ", SL=", sl,
          ", TP=", tp);
          
    int ticket = isLong ? 
        trade.Buy(Level1Volume, _Symbol, 0, sl, tp, "Hedge Level 1") :
        trade.Sell(Level1Volume, _Symbol, 0, sl, tp, "Hedge Level 1");
        
    if(ticket > 0) {
        Print("Level 1 order placed successfully, ticket #", ticket);
        
        // Store Level 1 details
        hedgeLevels[0].ticket = ticket;
        hedgeLevels[0].isLong = isLong;
        hedgeLevels[0].entryPrice = entryPrice;  // This becomes our base entry price for all levels
        hedgeLevels[0].stopLoss = sl;
        hedgeLevels[0].takeProfit = tp;
        hedgeLevels[0].volume = Level1Volume;
        hedgeLevels[0].isActive = true;
        
        // Create Level 1 labels
        UpdatePriceLabels(0);
        
        Print("Level 1 details stored and labels created");
        
        // Only place Level 2 order initially
        if(hedgeLevels[0].isActive) {
            double level2Entry = hedgeLevels[0].entryPrice + (Channel * pipValue * (hedgeLevels[0].isLong ? -1 : 1));
            PlacePendingOrder(1, !hedgeLevels[0].isLong, level2Entry);
        }
        
        isInitialTradeOpen = true;
        Print("Initial trade setup completed");
    } else {
        Print("Failed to place Level 1 order. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Place pending order for next level                                |
//+------------------------------------------------------------------+
void PlacePendingOrder(int level, bool isLong, double baseEntryPrice)
{
    // Prevent duplicate orders
    if(hedgeLevels[level].ticket != 0) {
        Print("Level ", level + 1, " already has ticket ", hedgeLevels[level].ticket);
        return;
    }

    // Get volume and SL/TP for this level
    double volume = 0.0;
    double sl = 0.0;
    double tp = 0.0;
    
    switch(level) {
        case 1: volume = Level2Volume; sl = Level2SL; tp = Level2TP; break;
        case 2: volume = Level3Volume; sl = Level3SL; tp = Level3TP; break;
        case 3: volume = Level4Volume; sl = Level4SL; tp = Level4TP; break;
        case 4: volume = Level5Volume; sl = Level5SL; tp = Level5TP; break;
        default: return;
    }

    // Calculate entry price and direction
    double nextEntryPrice;
    bool isOddLevel = (level % 2 == 0);  // level 2->odd, 3->even, 4->odd, 5->even
    
    // For buy stops, add a small offset to ensure price is above current
    double priceOffset = isLong ? (2 * _Point) : 0;
    
    // Copy exact price from L1 or L2
    nextEntryPrice = isOddLevel ? 
        (hedgeLevels[0].entryPrice + priceOffset) :     // Levels 3,5 use L1 entry + offset
        (hedgeLevels[0].entryPrice - (Channel * pipValue));  // Levels 2,4 use L1 entry - Channel
    
    // Direction alternates opposite to L1
    isLong = isOddLevel ? hedgeLevels[0].isLong : !hedgeLevels[0].isLong;

    // Calculate SL/TP prices
    double stopLoss = isLong ? nextEntryPrice - sl * pipValue : nextEntryPrice + sl * pipValue;
    double takeProfit = isLong ? nextEntryPrice + tp * pipValue : nextEntryPrice - tp * pipValue;

    Print("=== Placing Level ", level + 1, " Stop Order ===");
    Print("Direction: ", (isLong ? "Buy Stop" : "Sell Stop"));
    Print("Entry: ", nextEntryPrice);
    Print("Volume: ", volume);
    
    // Place the stop order
    trade.SetExpertMagicNumber(123456);
    if(isLong) {
        trade.BuyStop(volume, nextEntryPrice, _Symbol, stopLoss, takeProfit, 0, 0, "Hedge Level " + IntegerToString(level + 1));
    } else {
        trade.SellStop(volume, nextEntryPrice, _Symbol, stopLoss, takeProfit, 0, 0, "Hedge Level " + IntegerToString(level + 1));
    }

    // Store the ticket number
    ulong ticket = trade.ResultOrder();
    if(ticket > 0) {
        hedgeLevels[level].ticket = ticket;
        hedgeLevels[level].isLong = isLong;
        hedgeLevels[level].entryPrice = nextEntryPrice;
        hedgeLevels[level].stopLoss = stopLoss;
        hedgeLevels[level].takeProfit = takeProfit;
        hedgeLevels[level].volume = volume;
        hedgeLevels[level].isActive = false;
        hedgeLevels[level].exitTime = 0;
        hedgeLevels[level].positionTicket = 0;
        hedgeLevels[level].statusChanged = false;
        
        Print("=== Level Status After Order ===");
        for(int i=0; i<5; i++) {
            if(hedgeLevels[i].ticket != 0) {
                Print("Level ", i+1, 
                      " Ticket: ", hedgeLevels[i].ticket,
                      " Active: ", hedgeLevels[i].isActive,
                      " Entry: ", hedgeLevels[i].entryPrice,
                      " Direction: ", (hedgeLevels[i].isLong ? "Buy" : "Sell"));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check level exit and cleanup                                       |
//+------------------------------------------------------------------+
bool CheckLevelExit(int level)
{
    if(level >= 5) return false;
    if(hedgeLevels[level].exitTime > 0) return false;
    
    // Only log level 3 status when there's a change
    static datetime lastL3DebugTime = 0;
    datetime currentTime = TimeCurrent();
    
    if(level == 2 && (currentTime - lastL3DebugTime >= 300 || hedgeLevels[level].statusChanged)) // Level 3 (index 2)
    {
        Print("Level 3 Status - ",
              "Ticket: ", hedgeLevels[level].ticket,
              " Active: ", hedgeLevels[level].isActive,
              " Entry: ", hedgeLevels[level].entryPrice,
              " Previous Level Active: ", hedgeLevels[level-1].isActive,
              " Previous Level Ticket: ", hedgeLevels[level-1].ticket);
              
        lastL3DebugTime = currentTime;
        hedgeLevels[level].statusChanged = false;
    }
    
    // Check if this level just became active and needs to place next level's pending order
    if(hedgeLevels[level].isActive && level < 4 && hedgeLevels[level + 1].ticket == 0) {
        if(level == 2) { // Debug for Level 3
            Print("Attempting to place Level ", level + 2, " order - Previous level active: ", hedgeLevels[level].isActive);
            Print("Level ", level + 2, " Entry Price Calculation:",
                  " Current Entry: ", hedgeLevels[level].entryPrice,
                  " Channel: ", Channel,
                  " PipValue: ", pipValue);
        }
        
        double nextEntryPrice = hedgeLevels[level].isLong ?
            hedgeLevels[level].entryPrice + MathAbs(Channel) * pipValue :  // Buy stop if long
            hedgeLevels[level].entryPrice - MathAbs(Channel) * pipValue;   // Sell stop if short
            
        PlacePendingOrder(level + 1, hedgeLevels[level].isLong, hedgeLevels[level].entryPrice);
    }
    
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Check if SL or TP hit
    bool slHit = (hedgeLevels[level].isLong && bid <= hedgeLevels[level].stopLoss) ||
                 (!hedgeLevels[level].isLong && ask >= hedgeLevels[level].stopLoss);
                 
    bool tpHit = (hedgeLevels[level].isLong && bid >= hedgeLevels[level].takeProfit) ||
                 (!hedgeLevels[level].isLong && ask <= hedgeLevels[level].takeProfit);
    
    if(slHit || tpHit) {
        hedgeLevels[level].exitTime = TimeCurrent();
        hedgeLevels[level].exitPrice = slHit ? hedgeLevels[level].stopLoss : hedgeLevels[level].takeProfit;
        
        if(tpHit) {
            // Check if this is highest active level
            bool isHighestLevel = true;
            for(int j=level+1; j<5; j++) {
                if(hedgeLevels[j].isActive) {
                    isHighestLevel = false;
                    break;
                }
            }
            
            if(isHighestLevel) {
                // Delete pending orders and their visualization ONLY if never activated
                for(int k=level+1; k<5; k++) {
                    if(hedgeLevels[k].ticket > 0 && !hedgeLevels[k].isActive && !hedgeLevels[k].exitTime) {
                        trade.OrderDelete(hedgeLevels[k].ticket);
                        Print("Deleting pending order for Level ", k+1, " (Ticket: ", hedgeLevels[k].ticket, ")");
                        hedgeLevels[k].ticket = 0;  // Clear the ticket
                        
                        // Delete ALL visualization objects for never-active orders
                        string prefix = "Level_" + IntegerToString(k+1);
                        ObjectDelete(0, prefix + "_Entry");
                        ObjectDelete(0, prefix + "_SL");
                        ObjectDelete(0, prefix + "_TP");
                        ObjectDelete(0, prefix + "_SL_Label");
                        ObjectDelete(0, prefix + "_TP_Label");
                        
                        // Also clear any label-specific data
                        hedgeLevels[k].exitTime = 0;
                        hedgeLevels[k].exitPrice = 0;
                        hedgeLevels[k].statusChanged = false;
                    }
                }
                hasHitTakeProfit = true;
            }
        }
        
        // Only update price labels for active orders
        if(hedgeLevels[level].isActive) {
            UpdatePriceLabels(level);
        }
        return tpHit;
    }
    
    return false;
}

// Helper function to check if this is the current active level
bool IsCurrentActiveLevel(int level) {
    // Find highest active level
    int highestActiveLevel = -1;
    for(int i=4; i>=0; i--) {
        if(hedgeLevels[i].isActive) {
            highestActiveLevel = i;
            break;
        }
    }
    return level == highestActiveLevel;
}

//+------------------------------------------------------------------+
//| Close all positions and clean up                                   |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            trade.PositionClose(PositionGetTicket(i));
        }
    }
    
    for(int i=OrdersTotal()-1; i>=0; i--) {
        if(OrderSelect(OrderGetTicket(i))) {
            trade.OrderDelete(OrderGetTicket(i));
        }
    }
    
    for(int i=0; i<5; i++) {
        string prefix = "Level_" + IntegerToString(i+1);
        ObjectDelete(0, prefix + "_Entry");
        ObjectDelete(0, prefix + "_SL");
        ObjectDelete(0, prefix + "_TP");
        hedgeLevels[i].isActive = false;
        hedgeLevels[i].ticket = 0;
    }
    
    isInitialTradeOpen = false;
    Comment("");
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("DEBUG - OnDeinit called with reason: ", reason);
    
    // Clean up all visualization objects
    for(int i=0; i<5; i++) {
        string prefix = "Level_" + IntegerToString(i+1);
        ObjectDelete(0, prefix + "_Entry");
        ObjectDelete(0, prefix + "_SL");
        ObjectDelete(0, prefix + "_TP");
    }
    
    Comment("");
    ChartRedraw(0);
}

// Update the InitLevel function to initialize the new field
void InitLevel(int level) {
    hedgeLevels[level].ticket = 0;
    hedgeLevels[level].isActive = false;
    hedgeLevels[level].entryPrice = 0.0;
    hedgeLevels[level].exitTime = 0;
    hedgeLevels[level].statusChanged = false;  // Initialize new field
}

// Update where order status changes occur to set statusChanged flag
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    // Check if position was opened
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        ulong dealTicket = trans.deal;
        if(dealTicket > 0) {
            if(HistoryDealSelect(dealTicket)) {
                ulong orderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                
                // Find corresponding level
                for(int i=0; i<5; i++) {
                    if(hedgeLevels[i].ticket == orderTicket || hedgeLevels[i].positionTicket == trans.position) {
                        Print("Level ", i+1, " Deal - Price: ", dealPrice, 
                              " Type: ", (dealType == DEAL_TYPE_BUY ? "Buy" : "Sell"));
                              
                        // If position opened from pending order
                        if(dealEntry == DEAL_ENTRY_IN) {
                            hedgeLevels[i].isActive = true;
                            hedgeLevels[i].statusChanged = true;
                            hedgeLevels[i].positionTicket = trans.position;
                            
                            // Check if this is Level 5
                            if(i == 4) {
                                HandleExit("Maximum Level (5) Reached");
                            }
                            // Only place next level's order when current level becomes active
                            else if(i < 4) {
                                Print("Level ", i+1, " Activated - Setting up Level ", i+2);
                                PlacePendingOrder(i+1, !hedgeLevels[i].isLong, hedgeLevels[i].entryPrice);
                            }
                        }
                        break;
                    }
                }
            }
        }
    }
    
    // When order status changes
    for(int i=0; i<5; i++) {
        if(hedgeLevels[i].ticket == trans.order || hedgeLevels[i].positionTicket == trans.position) {
            if(trans.type <= 2) {
                hedgeLevels[i].statusChanged = true;
            }
            break;
        }
    }
}

void HandleExit(string reason)
{
    // Set flags
    maxLevelReached = true;
    hasHitTakeProfit = true;
    
    // Delete any pending orders
    for(int i=0; i<5; i++) {
        if(hedgeLevels[i].ticket > 0 && !hedgeLevels[i].isActive) {
            trade.OrderDelete(hedgeLevels[i].ticket);
            Print("Deleting pending order for Level ", i+1, " (Ticket: ", hedgeLevels[i].ticket, ")");
            hedgeLevels[i].ticket = 0;  // Clear the ticket
        }
    }
    
    Print("Strategy Exit - Reason: ", reason, 
          " - All pending orders deleted, no new orders will be placed");
}

void OnTrade()
{
    // First check for cancelled pending orders or manually closed active positions
    for(int i=0; i<5; i++) {
        if(hedgeLevels[i].ticket > 0) {
            bool orderExists = false;
            
            // Check if pending order still exists
            if(!hedgeLevels[i].isActive) {
                orderExists = OrderSelect(hedgeLevels[i].ticket);
            }
            // Check if active position still exists
            else {
                orderExists = PositionSelectByTicket(hedgeLevels[i].ticket);
            }
            
            // If order/position no longer exists
            if(!orderExists) {
                if(!hedgeLevels[i].isActive) {
                    // Clean up cancelled pending order
                    Print("Pending order cancelled for Level ", i+1);
                    string prefix = "Level_" + IntegerToString(i+1);
                    ObjectDelete(0, prefix + "_Entry");
                    ObjectDelete(0, prefix + "_SL");
                    ObjectDelete(0, prefix + "_TP");
                    ObjectDelete(0, prefix + "_SL_Label");
                    ObjectDelete(0, prefix + "_TP_Label");
                    hedgeLevels[i].ticket = 0;
                }
                else {
                    // Handle closed active position
                    Print("Active position closed for Level ", i+1);
                    hedgeLevels[i].exitTime = TimeCurrent();
                    hedgeLevels[i].exitPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
                    UpdatePriceLabels(i);  // This will show final P/L
                }
            }
        }
    }

    // First check if any active level hit TP
    for(int i=0; i<5; i++) {
        if(hedgeLevels[i].isActive && !hedgeLevels[i].exitTime) {
            bool hitTP = CheckLevelExit(i);
            if(hitTP) {
                // Only exit strategy if this was the highest active level and it hit TP
                bool isHighestLevel = true;
                for(int j=i+1; j<5; j++) {
                    if(hedgeLevels[j].isActive) {
                        isHighestLevel = false;
                        break;
                    }
                }
                
                if(isHighestLevel) {
                    // Delete all pending orders for higher levels
                    for(int k=i+1; k<5; k++) {
                        if(hedgeLevels[k].ticket > 0 && !hedgeLevels[k].isActive) {
                            trade.OrderDelete(hedgeLevels[k].ticket);
                            Print("Deleting pending order for Level ", k+1, " (Ticket: ", hedgeLevels[k].ticket, ")");
                            hedgeLevels[k].ticket = 0;  // Clear the ticket
                        }
                    }
                    HandleExit("Take Profit hit on highest active level " + IntegerToString(i+1));
                    return;  // Exit immediately to prevent further order placement
                }
                // Otherwise continue - let other levels activate up to max level
            }
        }
    }

    // Then check for order activations
    for(int i=0; i<5; i++) {
        if(hedgeLevels[i].ticket > 0 && !hedgeLevels[i].isActive) {
            // Check if order was filled
            if(HistoryOrderSelect(hedgeLevels[i].ticket)) {
                if(HistoryOrderGetInteger(hedgeLevels[i].ticket, ORDER_TIME_DONE) > 0) {  // Order was filled/activated
                    hedgeLevels[i].isActive = true;
                    hedgeLevels[i].positionTicket = HistoryOrderGetInteger(hedgeLevels[i].ticket, ORDER_TICKET);
                    Print("Level ", i+1, " Order Activated");
                    
                    // If this was Level 5 becoming active, exit strategy
                    if(i == 4) {
                        HandleExit("Maximum Level (5) Reached");
                        return;
                    }
                    
                    // Otherwise place next level's orders
                    if(i < 4) {
                        PlacePendingOrder(i+1, hedgeLevels[0].isLong, hedgeLevels[0].entryPrice);
                        
                        // If this was Level 4 becoming active, place Level 5
                        if(i == 3) {
                            PlacePendingOrder(4, hedgeLevels[0].isLong, hedgeLevels[0].entryPrice);
                        }
                    }
                }
            }
        }
    }
}

void CheckExitConditions()
{
    // Check for exit conditions
    for(int i=0; i<5; i++) {
        if(hedgeLevels[i].ticket > 0 || hedgeLevels[i].isActive) {
            CheckLevelExit(i);
            UpdatePriceLabels(i);
        }
    }
    
    UpdateVisualization();
}
