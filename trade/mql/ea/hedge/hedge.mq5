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
double          initialChartRange = 0;      // Store initial chart range
double          initialOffsetSize = 0;      // Store initial offset size

struct HedgeLevel {
    int ticket;         // Order ticket
    bool isLong;       // Direction
    double entryPrice; // Entry price
    double stopLoss;   // Stop loss price
    double takeProfit; // Take profit price
    double volume;     // Volume in lots
    bool isActive;     // Whether this level is active
    datetime exitTime; // Time when the level exited (0 if not exited)
    double exitPrice; // Price at which the level exited
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
    
    // If level has exited, use stored exit values
    if(hedgeLevels[level].exitTime > 0) {
        double slDollarValue = CalculateDollarValue(hedgeLevels[level].exitPrice, 
                                                  hedgeLevels[level].entryPrice,
                                                  hedgeLevels[level].isLong,
                                                  hedgeLevels[level].volume);
                                                  
        // Update or create SL label at exit point
        if(ObjectFind(0, slLabelName) >= 0) {
            ObjectSetInteger(0, slLabelName, OBJPROP_TIME, hedgeLevels[level].exitTime);
            ObjectSetString(0, slLabelName, OBJPROP_TEXT, StringFormat("$%.2f", slDollarValue));
        } else {
            ObjectCreate(0, slLabelName, OBJ_TEXT, 0, hedgeLevels[level].exitTime, hedgeLevels[level].exitPrice);
            ObjectSetString(0, slLabelName, OBJPROP_TEXT, StringFormat("$%.2f", slDollarValue));
            ObjectSetInteger(0, slLabelName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, slLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
            ObjectSetInteger(0, slLabelName, OBJPROP_FONTSIZE, 8);
        }
        
        // Remove TP label for exited level
        ObjectDelete(0, tpLabelName);
        return;
    }
    
    // Normal label updates for active levels
    double slDollarValue = CalculateDollarValue(hedgeLevels[level].stopLoss, 
                                              hedgeLevels[level].entryPrice,
                                              hedgeLevels[level].isLong,
                                              hedgeLevels[level].volume);
                                              
    double tpDollarValue = CalculateDollarValue(hedgeLevels[level].takeProfit,
                                              hedgeLevels[level].entryPrice,
                                              hedgeLevels[level].isLong,
                                              hedgeLevels[level].volume);
    
    datetime currentTime = TimeCurrent();
    datetime labelTime = currentTime + (PeriodSeconds() * 2);
    
    // Update active level labels
    if(ObjectFind(0, slLabelName) >= 0) {
        ObjectSetInteger(0, slLabelName, OBJPROP_TIME, labelTime);
        ObjectSetString(0, slLabelName, OBJPROP_TEXT, StringFormat("$%.2f", slDollarValue));
    } else {
        ObjectCreate(0, slLabelName, OBJ_TEXT, 0, labelTime, hedgeLevels[level].stopLoss);
        ObjectSetString(0, slLabelName, OBJPROP_TEXT, StringFormat("$%.2f", slDollarValue));
        ObjectSetInteger(0, slLabelName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, slLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetInteger(0, slLabelName, OBJPROP_FONTSIZE, 8);
    }
    
    if(ObjectFind(0, tpLabelName) >= 0) {
        ObjectSetInteger(0, tpLabelName, OBJPROP_TIME, labelTime);
        ObjectSetString(0, tpLabelName, OBJPROP_TEXT, StringFormat("$%.2f", tpDollarValue));
    } else {
        ObjectCreate(0, tpLabelName, OBJ_TEXT, 0, labelTime, hedgeLevels[level].takeProfit);
        ObjectSetString(0, tpLabelName, OBJPROP_TEXT, StringFormat("$%.2f", tpDollarValue));
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
    // Place initial trade if not already done
    if(!isInitialTradeOpen) {
        OpenInitialTrade();
        return;
    }
    
    // Update all active level labels
    for(int i=0; i<5; i++) {
        UpdatePriceLabels(i);
    }
    
    // Check for level activation
    for(int i=0; i<5; i++) {
        if(hedgeLevels[i].ticket > 0) {
            // Check if pending order was activated
            if(!hedgeLevels[i].isActive && OrderSelect(hedgeLevels[i].ticket)) {
                hedgeLevels[i].isActive = true;
                
                // Place next level order when this one activates (if not already placed)
                if(i < 4 && hedgeLevels[i + 1].ticket == 0) {
                    double nextEntryPrice = hedgeLevels[i].isLong ?
                        hedgeLevels[i].entryPrice - MathAbs(Channel) * pipValue :
                        hedgeLevels[i].entryPrice + MathAbs(Channel) * pipValue;
                        
                    PlacePendingOrder(i + 1, !hedgeLevels[i].isLong, nextEntryPrice);
                }
            }
        }
        
        if(hedgeLevels[i].isActive) {
            CheckLevelExit(i);
        }
    }
    
    UpdateVisualization();
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
   if(TimeCurrent() - lastVisualizationUpdate < VISUALIZATION_UPDATE_INTERVAL) {
      return;
   }
   
   lastVisualizationUpdate = TimeCurrent();
   
   // Only delete our specific custom objects
   for(int i=0; i<5; i++) {
       string prefix = "Level_" + IntegerToString(i+1);
       ObjectDelete(0, prefix + "_Entry");
       ObjectDelete(0, prefix + "_SL");
       ObjectDelete(0, prefix + "_TP");
   }
   
   ObjectDelete(0, "Channel_Upper");
   ObjectDelete(0, "Channel_Lower");
   
   // Draw channel borders based on initial entry
   double baseEntry = hedgeLevels[0].entryPrice;
   double channelEntry = baseEntry - MathAbs(Channel) * pipValue;
   
   // Draw channel lines with neutral colors
   DrawLine("Channel_Upper", baseEntry, clrGray);
   DrawLine("Channel_Lower", channelEntry, clrGray);
   
   // Draw active levels and pending orders
   for(int i=0; i<5; i++) {
       if(hedgeLevels[i].isActive || (i > 0 && hedgeLevels[i-1].isActive)) {
           string prefix = "Level_" + IntegerToString(i+1);
           color levelColor = levelColors[i];
           
           Print("Drawing Level ", i+1, " with color: ", ColorToString(levelColor));
           
           // Entry will be either at baseEntry or channel entry
           double entryPrice = (i % 2 == 1) ? channelEntry : baseEntry;
           
           // Draw entry line
           ObjectCreate(0, prefix + "_Entry", OBJ_HLINE, 0, 0, entryPrice);
           ObjectSetInteger(0, prefix + "_Entry", OBJPROP_COLOR, levelColor);
           ObjectSetInteger(0, prefix + "_Entry", OBJPROP_STYLE, STYLE_SOLID);
           ObjectSetInteger(0, prefix + "_Entry", OBJPROP_WIDTH, 2);  // Make lines thicker
           
           // Draw SL line
           ObjectCreate(0, prefix + "_SL", OBJ_HLINE, 0, 0, hedgeLevels[i].stopLoss);
           ObjectSetInteger(0, prefix + "_SL", OBJPROP_COLOR, levelColor);
           ObjectSetInteger(0, prefix + "_SL", OBJPROP_STYLE, STYLE_DOT);
           ObjectSetInteger(0, prefix + "_SL", OBJPROP_WIDTH, 1);
           
           // Draw TP line
           ObjectCreate(0, prefix + "_TP", OBJ_HLINE, 0, 0, hedgeLevels[i].takeProfit);
           ObjectSetInteger(0, prefix + "_TP", OBJPROP_COLOR, levelColor);
           ObjectSetInteger(0, prefix + "_TP", OBJPROP_STYLE, STYLE_DASH);
           ObjectSetInteger(0, prefix + "_SL", OBJPROP_WIDTH, 1);
       }
   }
   
   ChartRedraw(0);
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
        
        // Calculate Level 2 entry price
        double pendingPrice = isLong ? 
            entryPrice - MathAbs(Channel) * pipValue :  // Sell Stop below for long
            entryPrice + MathAbs(Channel) * pipValue;   // Buy Stop above for short
            
        Print("Attempting to place Level 2 order at price: ", pendingPrice);
        
        // Place Level 2 pending order
        PlacePendingOrder(1, !isLong, entryPrice);  // Pass original entry price as base
        
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
    Print("Starting PlacePendingOrder: Level=", level+1, 
          ", Direction=", isLong ? "Long" : "Short",
          ", BaseEntry=", baseEntryPrice);
          
    if(level >= 5) {
        Print("Level too high, not placing order");
        return;
    }
    
    // Only two possible entry prices:
    // 1. Base Entry (original entry price)
    // 2. Channel Entry (base entry - channel)
    double channelEntry = baseEntryPrice - MathAbs(Channel) * pipValue;
    
    // Odd levels (2,4) use channel entry
    // Even levels (1,3,5) use base entry
    double entryPrice = (level % 2 == 1) ? channelEntry : baseEntryPrice;
    
    double volume = level == 1 ? Level2Volume :
                   level == 2 ? Level3Volume :
                   level == 3 ? Level4Volume :
                   Level5Volume;
                   
    double slPips = level == 1 ? Level2SL :
                    level == 2 ? Level3SL :
                    level == 3 ? Level4SL :
                    Level5SL;
                    
    double tpPips = level == 1 ? Level2TP :
                    level == 2 ? Level3TP :
                    level == 3 ? Level4TP :
                    Level5TP;
    
    double sl = isLong ? entryPrice - slPips * pipValue : entryPrice + slPips * pipValue;
    double tp = isLong ? entryPrice + tpPips * pipValue : entryPrice - tpPips * pipValue;
    
    ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
    
    Print("Placing pending order: ", 
          "Type=", EnumToString(orderType),
          ", Volume=", volume,
          ", Entry=", entryPrice,
          ", SL=", sl,
          ", TP=", tp);
    
    // Let's add more detailed logging for the order parameters
    Print("Order details:",
          "\nSymbol: ", _Symbol,
          "\nType: ", EnumToString(orderType),
          "\nVolume: ", volume,
          "\nPrice: ", entryPrice,
          "\nStopLoss: ", sl,
          "\nTakeProfit: ", tp,
          "\nComment: Hedge Level ", level + 1);
    
    int ticket = trade.OrderOpen(_Symbol,    // symbol
                               orderType,    // order type
                               volume,       // volume
                               entryPrice,   // limit/stop price
                               entryPrice,   // activation price
                               sl,          // stop loss
                               tp,          // take profit
                               ORDER_TIME_GTC,  // time type
                               0,           // expiration
                               "Hedge Level " + IntegerToString(level + 1));
                               
    if(ticket > 0) {
        Print("Successfully placed pending order ticket #", ticket);
        
        hedgeLevels[level].ticket = ticket;
        hedgeLevels[level].isLong = isLong;
        hedgeLevels[level].entryPrice = entryPrice;
        hedgeLevels[level].stopLoss = sl;
        hedgeLevels[level].takeProfit = tp;
        hedgeLevels[level].volume = volume;
        hedgeLevels[level].isActive = false;  // Will become active when triggered
        
        // Create labels for pending order
        UpdatePriceLabels(level);
        
        Print("Level ", level+1, " details stored and labels created");
    } else {
        Print("Failed to place pending order. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Clean up visualization objects for a specific level                |
//+------------------------------------------------------------------+
void CleanupLevelVisualization(int level)
{
    Print("DEBUG - Cleaning up visualization for level ", level);  // Debug print
    
    string basePrefix = "Level_" + IntegerToString(level+1);
    
    // Store object names for verification
    string entryName = basePrefix + "_Entry";
    string slName = basePrefix + "_SL";
    string tpName = basePrefix + "_TP";
    string slLabelName = basePrefix + "_SL_Label";
    string tpLabelName = basePrefix + "_TP_Label";
    
    // Delete objects and verify
    if(ObjectDelete(0, entryName)) Print("Deleted entry line");
    if(ObjectDelete(0, slName)) Print("Deleted SL line");
    if(ObjectDelete(0, tpName)) Print("Deleted TP line");
    if(ObjectDelete(0, slLabelName)) Print("Deleted SL label");
    if(ObjectDelete(0, tpLabelName)) Print("Deleted TP label");
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Close all positions and clean up                                   |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    Print("DEBUG - CloseAllPositions called");  // Debug print
    
    // Close all positions
    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            Print("Closing position ticket #", PositionGetTicket(i));
            trade.PositionClose(PositionGetTicket(i));
        }
    }
    
    // Delete all pending orders
    for(int i=OrdersTotal()-1; i>=0; i--) {
        if(OrderSelect(OrderGetTicket(i))) {
            Print("Deleting order ticket #", OrderGetTicket(i));
            trade.OrderDelete(OrderGetTicket(i));
        }
    }
    
    // Reset state and clean up visualization
    for(int i=0; i<5; i++) {
        Print("DEBUG - Cleaning up level ", i);  // Debug print
        CleanupLevelVisualization(i);
        hedgeLevels[i].isActive = false;
        hedgeLevels[i].ticket = 0;
    }
    
    isInitialTradeOpen = false;
    Comment("");  // Clear any comments
    ChartRedraw(0);
    Print("DEBUG - CloseAllPositions completed");  // Debug print
}

//+------------------------------------------------------------------+
//| Check level exit and cleanup                                       |
//+------------------------------------------------------------------+
void CheckLevelExit(int level)
{
    if(level >= 5) return;
    
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Check if TP hit
    if((hedgeLevels[level].isLong && bid >= hedgeLevels[level].takeProfit) ||
       (!hedgeLevels[level].isLong && ask <= hedgeLevels[level].takeProfit)) {
        // Store exit information
        hedgeLevels[level].exitTime = TimeCurrent();
        hedgeLevels[level].exitPrice = hedgeLevels[level].takeProfit;
        CloseAllPositions();
        return;
    }
    
    // Check if SL hit
    if((hedgeLevels[level].isLong && bid <= hedgeLevels[level].stopLoss) ||
       (!hedgeLevels[level].isLong && ask >= hedgeLevels[level].stopLoss)) {
        // Store exit information
        hedgeLevels[level].exitTime = TimeCurrent();
        hedgeLevels[level].exitPrice = hedgeLevels[level].stopLoss;
        
        // Clean up current level visualization
        CleanupLevelVisualization(level);
        
        // Reset current level's state but keep exit information
        hedgeLevels[level].isActive = false;
        hedgeLevels[level].ticket = 0;
        
        if(level < 4 && hedgeLevels[level + 1].ticket == 0) {
            double nextEntryPrice = hedgeLevels[level].isLong ?
                hedgeLevels[level].entryPrice - MathAbs(Channel) * pipValue :
                hedgeLevels[level].entryPrice + MathAbs(Channel) * pipValue;
                
            PlacePendingOrder(level + 1, !hedgeLevels[level].isLong, nextEntryPrice);
        }
    }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("DEBUG - OnDeinit called with reason: ", reason);  // Debug print
    
    // Clean up all visualization objects
    for(int i=0; i<5; i++) {
        CleanupLevelVisualization(i);
    }
    
    Comment("");  // Clear any comments
    ChartRedraw(0);
}
