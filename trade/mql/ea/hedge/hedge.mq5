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
bool          isInitialTradeOpen = false;   // Flag to track if first trade is open

// Define level colors at the top with other global variables
color levelColors[5] = {
    clrOrange,        // Level 1 - Orange
    clrDodgerBlue,    // Level 2 - Light Blue
    clrGold,          // Level 3 - Yellow/Gold
    clrAquamarine,    // Level 4 - Light Green
    clrMagenta        // Level 5 - Purple
};

// Define the possible states for a level
enum LEVEL_STATE {
    STATE_NONE,           // Level not initialized
    STATE_PENDING,        // Pending order placed
    STATE_ACTIVE,         // Position is active
    STATE_CLOSED,         // Position has been closed
    STATE_CANCELLED       // Order was cancelled
};

// Structure to track complete level status
struct LevelStatus {
    int level;              // Level number (1-5)
    LEVEL_STATE state;      // Current state of the level
    bool isLong;           // Direction
    double entryPrice;     // Entry price
    double stopLoss;       // Stop loss price
    double takeProfit;     // Take profit price
    double volume;         // Volume in lots
    ulong orderTicket;     // Ticket for pending order
    ulong positionTicket;  // Ticket for active position
    datetime exitTime;     // Time when position closed
    double exitPrice;      // Price at which position closed
    
    // Constructor
    void LevelStatus() {
        Reset();
    }
    
    // Reset all values
    void Reset() {
        state = STATE_NONE;
        isLong = false;
        entryPrice = 0.0;
        stopLoss = 0.0;
        takeProfit = 0.0;
        volume = 0.0;
        orderTicket = 0;
        positionTicket = 0;
        exitTime = 0;
        exitPrice = 0.0;
    }
    
    // Update state and tickets
    void SetPending(ulong ticket) {
        state = STATE_PENDING;
        orderTicket = ticket;
        positionTicket = 0;
    }
    
    void SetActive(ulong position) {
        state = STATE_ACTIVE;
        positionTicket = position;
    }
    
    void SetClosed(double closePrice) {
        state = STATE_CLOSED;
        exitTime = TimeCurrent();
        exitPrice = closePrice;
    }
    
    void SetCancelled() {
        state = STATE_CANCELLED;
        orderTicket = 0;
        positionTicket = 0;
    }
};

// Array to store level statuses (static allocation)
LevelStatus levels[5];  // Fixed size array of 5 levels

// Add timer to control visualization updates
static datetime lastVisualizationUpdate = 0;
const int VISUALIZATION_UPDATE_INTERVAL = 5; // Seconds

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize each level in the array
    for(int i=0; i<5; i++) {
        levels[i].Reset();        // Reset all values
        levels[i].level = i + 1;  // Set level number
    }
    
    // Reset the TP flag on initialization
    hasHitTakeProfit = false;
    
    trade.SetExpertMagicNumber(123456);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    pipValue = (symbolDigits == 3 || symbolDigits == 5) ? point * 10 : point;
    
    // Set up timer for regular updates (every 1 second)
    EventSetTimer(1);
    
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
    string basePrefix = "Level_" + IntegerToString(level+1);
    string entryLineName = basePrefix + "_Entry";
    string slLineName = basePrefix + "_SL";
    string tpLineName = basePrefix + "_TP";
    
    // Use the global level colors defined at the top of the file
    color lineColor = levelColors[level];  // Using the global array: clrOrange, clrDodgerBlue, clrGold, etc.
    
    if(levels[level].state == STATE_ACTIVE || levels[level].state == STATE_PENDING) {
        // Create or update entry line
        if(ObjectFind(0, entryLineName) < 0) {
            ObjectCreate(0, entryLineName, OBJ_HLINE, 0, 0, levels[level].entryPrice);
            ObjectSetInteger(0, entryLineName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(0, entryLineName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, entryLineName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetString(0, entryLineName, OBJPROP_TEXT, 
                          "L" + IntegerToString(level+1) + " Entry " + 
                          (levels[level].isLong ? "Long" : "Short"));
        } else {
            ObjectMove(0, entryLineName, 0, 0, levels[level].entryPrice);
        }
        
        // Create or update SL line
        if(ObjectFind(0, slLineName) < 0) {
            ObjectCreate(0, slLineName, OBJ_HLINE, 0, 0, levels[level].stopLoss);
            ObjectSetInteger(0, slLineName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(0, slLineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, slLineName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetString(0, slLineName, OBJPROP_TEXT, 
                          "L" + IntegerToString(level+1) + " SL " + 
                          DoubleToString(MathAbs(levels[level].stopLoss - levels[level].entryPrice) / pipValue, 1) + " pips");
        } else {
            ObjectMove(0, slLineName, 0, 0, levels[level].stopLoss);
        }
        
        // Create or update TP line
        if(ObjectFind(0, tpLineName) < 0) {
            ObjectCreate(0, tpLineName, OBJ_HLINE, 0, 0, levels[level].takeProfit);
            ObjectSetInteger(0, tpLineName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(0, tpLineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, tpLineName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetString(0, tpLineName, OBJPROP_TEXT, 
                          "L" + IntegerToString(level+1) + " TP " + 
                          DoubleToString(MathAbs(levels[level].takeProfit - levels[level].entryPrice) / pipValue, 1) + " pips");
        } else {
            ObjectMove(0, tpLineName, 0, 0, levels[level].takeProfit);
        }
        
        ChartRedraw(0);
    }
    else if(levels[level].state == STATE_CLOSED || levels[level].state == STATE_NONE) {
        Print("L1 Cleanup - Deleting lines for level ", level + 1);
        
        if(ObjectFind(0, entryLineName) >= 0) {
            ObjectDelete(0, entryLineName);
            Print("Deleted entry line");
        }
        if(ObjectFind(0, slLineName) >= 0) {
            ObjectDelete(0, slLineName);
            Print("Deleted SL line");
        }
        if(ObjectFind(0, tpLineName) >= 0) {
            ObjectDelete(0, tpLineName);
            Print("Deleted TP line");
        }
        
        ChartRedraw(0);
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
            if(levels[i].state == STATE_ACTIVE) {
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
                                                    levels[nextLevel].entryPrice,
                                                    levels[nextLevel].isLong,
                                                    levels[nextLevel].volume);
                                                    
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
                levels[nextLevel].stopLoss = newPrice;
            } else {
                levels[nextLevel].takeProfit = newPrice;
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
       if(levels[i].state == STATE_ACTIVE) {
           highestActiveLevel = i;
           break;
       }
   }
   
   // Check each level's orders
   for(int i=0; i<=highestActiveLevel+1 && i<5; i++) {
       if(levels[i].orderTicket > 0) {
           // Check if order is still open
           if(OrderSelect(levels[i].orderTicket)) {
               // If pending order
               if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP || 
                  OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) {
                   // Check if triggered
                   if(levels[i].state != STATE_ACTIVE) {
                       // Update status if order was triggered
                       if(PositionSelectByTicket(levels[i].orderTicket)) {
                           levels[i].state = STATE_ACTIVE;
                           
                           // Place next level's pending order
                           if(i < 4) {  // Don't place after level 5
                               PlacePendingOrder(i + 1, !levels[i].isLong, levels[0].entryPrice);
                           }
                       }
                   }
               }
           }
           
           // Check for TP/SL hits
           if(levels[i].state == STATE_ACTIVE) {
               CheckLevelExit(i);
           }
       }
   }
}

//+------------------------------------------------------------------+
//| Clean up visualization for a specific level                        |
//+------------------------------------------------------------------+
void CleanupLevelVisualization(int level)
{
    string prefix = "Level_" + IntegerToString(level+1);
    ObjectDelete(0, prefix + "_Entry");
    ObjectDelete(0, prefix + "_SL");
    ObjectDelete(0, prefix + "_TP");
    ObjectDelete(0, prefix + "_SL_Label");
    ObjectDelete(0, prefix + "_TP_Label");
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Update visualization                                               |
//+------------------------------------------------------------------+
void UpdateVisualization()
{
    // Calculate base prices
    double baseEntry = levels[0].entryPrice;
    if(baseEntry == 0) return;  // Don't update if no base entry exists
    
    // Draw channel borders
    DrawLine("Channel_Upper", baseEntry, clrGray, STYLE_SOLID, 1);
    DrawLine("Channel_Lower", baseEntry - MathAbs(Channel) * pipValue, clrGray, STYLE_SOLID, 1);
    
    // Rate limit updates to once per second
    static datetime lastUpdate = 0;
    datetime currentTime = TimeCurrent();
    if(currentTime - lastUpdate < 1) return;
    lastUpdate = currentTime;
    
    // Update level visualizations
    for(int i=0; i<5; i++) {
        if(levels[i].orderTicket > 0 || levels[i].state == STATE_ACTIVE) {
            UpdatePriceLabels(i);
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
//| Open initial trade (Level 1)                                       |
//+------------------------------------------------------------------+
bool OpenInitialTrade()
{
    Print("Starting OpenInitialTrade");
    
    // Determine direction from Channel input
    bool isLong = Channel > 0;
    
    // Calculate entry price for market order (current bid/ask)
    double entryPrice = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate SL and TP based on direction
    double slPrice, tpPrice;
    if(isLong) {
        slPrice = entryPrice - (Level1SL * pipValue);
        tpPrice = entryPrice + (Level1TP * pipValue);
    } else {
        slPrice = entryPrice + (Level1SL * pipValue);  // Add for short SL
        tpPrice = entryPrice - (Level1TP * pipValue);  // Subtract for short TP
    }
    
    Print("Attempting Level 1 order: Direction=", (isLong ? "Long" : "Short"), 
          ", Entry=", entryPrice, 
          ", SL=", slPrice, 
          ", TP=", tpPrice);
          
    // Place the market order
    trade.PositionOpen(Symbol(), 
                      isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                      Level1Volume,
                      entryPrice,
                      slPrice,
                      tpPrice,
                      "Level 1");
    
    // Initialize Level 1 status
    levels[0].level = 1;
    levels[0].state = STATE_ACTIVE;
    levels[0].isLong = isLong;
    levels[0].entryPrice = entryPrice;
    levels[0].stopLoss = slPrice;
    levels[0].takeProfit = tpPrice;
    levels[0].volume = Level1Volume;
    levels[0].orderTicket = 1;  // Special case for market order
    
    Print("Level 1 order placed successfully, ticket #1");
    
    // Update visualization
    UpdatePriceLabels(0);
    Print("Level 1 details stored and visualization created");
    
    // Calculate channel boundaries based on L1 fill price
    double channelTop = isLong ? entryPrice : entryPrice - (MathAbs(Channel) * pipValue);
    double channelBottom = isLong ? entryPrice - (MathAbs(Channel) * pipValue) : entryPrice;
    
    Print("Channel established - Top: ", channelTop, " Bottom: ", channelBottom);
    
    // Do NOT place Level 2 order here - it will be placed in OnTradeTransaction
    // when Level 1's position ticket is received
    
    isInitialTradeOpen = true;
    Print("Initial trade setup completed");
    return true;
}

//+------------------------------------------------------------------+
//| Place pending order for next level                                 |
//+------------------------------------------------------------------+
bool PlacePendingOrder(int level, bool isLong, double basePrice)
{
    // Verify previous level is active before placing new order
    if(level > 0 && levels[level-1].state != STATE_ACTIVE) {
        Print("Cannot place Level ", level+1, " order - Level ", level, " not yet active");
        return false;
    }
    
    // Get channel boundaries based on Level 1's fill price
    double channelTop = levels[0].isLong ? levels[0].entryPrice : levels[0].entryPrice - (Channel * pipValue);
    double channelBottom = levels[0].isLong ? levels[0].entryPrice - (Channel * pipValue) : levels[0].entryPrice;
    
    Print("Channel Boundaries - Top: ", channelTop, " Bottom: ", channelBottom);
    
    double volume = 0.0;
    double slPips = 0.0;
    double tpPips = 0.0;
    
    // Set parameters based on level
    switch(level + 1) {
        case 2:
            volume = Level2Volume;
            slPips = Level2SL;
            tpPips = Level2TP;
            break;
        case 3:
            volume = Level3Volume;
            slPips = Level3SL;
            tpPips = Level3TP;
            break;
        case 4:
            volume = Level4Volume;
            slPips = Level4SL;
            tpPips = Level4TP;
            break;
        case 5:
            volume = Level5Volume;
            slPips = Level5SL;
            tpPips = Level5TP;
            break;
    }
    
    // Entry price must be at one of the channel boundaries
    double entryPrice = isLong ? channelTop : channelBottom;
    double slPrice = isLong ? entryPrice - (slPips * pipValue) : entryPrice + (slPips * pipValue);
    double tpPrice = isLong ? entryPrice + (tpPips * pipValue) : entryPrice - (tpPips * pipValue);
    
    Print("Level ", level + 1, " Entry: ", entryPrice, " (", (isLong ? "Buy" : "Sell"), " Stop)");
    Print("Volume: ", volume);
    
    // Place the pending order
    ulong ticket = trade.OrderOpen(_Symbol, 
                                 isLong ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP,
                                 volume, 0, entryPrice, slPrice, tpPrice,
                                 ORDER_TIME_GTC, 0, "Level " + IntegerToString(level + 1));
    
    if(ticket == 0) {
        Print("Failed to place Level ", level + 1, " order: ", GetLastError());
        return false;
    }
    
    // Initialize level status
    levels[level].level = level + 1;
    levels[level].state = STATE_PENDING;
    levels[level].isLong = isLong;
    levels[level].entryPrice = entryPrice;
    levels[level].stopLoss = slPrice;
    levels[level].takeProfit = tpPrice;
    levels[level].volume = volume;
    levels[level].orderTicket = ticket;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check level exit and cleanup                                       |
//+------------------------------------------------------------------+
bool CheckLevelExit(int level)
{
    if(levels[level].orderTicket <= 0 && levels[level].state != STATE_ACTIVE) return false;
    
    bool positionExists = false;
    if(levels[level].positionTicket > 0) {
        positionExists = PositionSelectByTicket(levels[level].positionTicket);
    }
    
    // If position was active but no longer exists, clean up
    if(levels[level].state == STATE_ACTIVE && !positionExists) {
        Print("Level ", level + 1, " position closed");
        levels[level].state = STATE_CLOSED;
        levels[level].exitTime = TimeCurrent();
        levels[level].orderTicket = 0;  // Clear ticket
        levels[level].positionTicket = 0;
        
        // Clear visualization
        string prefix = "Level" + IntegerToString(level + 1);
        ObjectDelete(0, prefix + "_Entry");
        ObjectDelete(0, prefix + "_SL");
        ObjectDelete(0, prefix + "_TP");
    }
    
    // Only log level 3 status when there's a change
    static datetime lastL3DebugTime = 0;
    datetime currentTime = TimeCurrent();
    
    if(level == 2 && (currentTime - lastL3DebugTime >= 300 || levels[level].state == STATE_ACTIVE)) // Level 3 (index 2)
    {
        Print("Level 3 Status - ",
              "Ticket: ", levels[level].orderTicket,
              " Active: ", levels[level].state == STATE_ACTIVE,
              " Entry: ", levels[level].entryPrice,
              " Previous Level Active: ", levels[level-1].state == STATE_ACTIVE,
              " Previous Level Ticket: ", levels[level-1].orderTicket);
              
        lastL3DebugTime = currentTime;
    }
    
    // Check if this level just became active and needs to place next level's pending order
    if(levels[level].state == STATE_ACTIVE && level < 4 && levels[level + 1].orderTicket == 0) {
        if(level == 2) { // Debug for Level 3
            Print("Attempting to place Level ", level + 2, " order - Previous level active: ", levels[level].state == STATE_ACTIVE);
            Print("Level ", level + 2, " Entry Price Calculation:",
                  " Current Entry: ", levels[level].entryPrice,
                  " Channel: ", Channel,
                  " PipValue: ", pipValue);
        }
        
        double nextEntryPrice = levels[level].isLong ?
            levels[level].entryPrice + MathAbs(Channel) * pipValue :  // Buy stop if long
            levels[level].entryPrice - MathAbs(Channel) * pipValue;   // Sell stop if short
            
        PlacePendingOrder(level + 1, levels[level].isLong, levels[level].entryPrice);
    }
    
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Check if SL or TP hit
    bool slHit = (levels[level].isLong && bid <= levels[level].stopLoss) ||
                 (!levels[level].isLong && ask >= levels[level].stopLoss);
                 
    bool tpHit = (levels[level].isLong && bid >= levels[level].takeProfit) ||
                 (!levels[level].isLong && ask <= levels[level].takeProfit);
    
    if(slHit || tpHit) {
        levels[level].exitTime = TimeCurrent();
        levels[level].exitPrice = slHit ? levels[level].stopLoss : levels[level].takeProfit;
        
        if(tpHit) {
            // Check if this is highest active level
            bool isHighestLevel = true;
            for(int j=level+1; j<5; j++) {
                if(levels[j].state == STATE_ACTIVE) {
                    isHighestLevel = false;
                    break;
                }
            }
            
            if(isHighestLevel) {
                // Delete pending orders and their visualization ONLY if never activated
                for(int k=level+1; k<5; k++) {
                    if(levels[k].orderTicket > 0 && levels[k].state != STATE_ACTIVE && levels[k].exitTime == 0) {
                        trade.OrderDelete(levels[k].orderTicket);
                        Print("Deleting pending order for Level ", k+1, " (Ticket: ", levels[k].orderTicket, ")");
                        levels[k].orderTicket = 0;  // Clear the ticket
                        
                        // Delete ALL visualization objects for never-active orders
                        string prefix = "Level_" + IntegerToString(k+1);
                        ObjectDelete(0, prefix + "_Entry");
                        ObjectDelete(0, prefix + "_SL");
                        ObjectDelete(0, prefix + "_TP");
                        ObjectDelete(0, prefix + "_SL_Label");
                        ObjectDelete(0, prefix + "_TP_Label");
                        
                        // Also clear any label-specific data
                        levels[k].exitTime = 0;
                        levels[k].exitPrice = 0;
                    }
                }
                hasHitTakeProfit = true;
            }
        }
        
        // Only update price labels for active orders
        if(levels[level].state == STATE_ACTIVE) {
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
        if(levels[i].state == STATE_ACTIVE) {
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
        levels[i].state = STATE_NONE;
        levels[i].orderTicket = 0;
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
    EventKillTimer();  // Remove timer
    
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
    levels[level].orderTicket = 0;
    levels[level].state = STATE_NONE;
    levels[level].entryPrice = 0.0;
    levels[level].exitTime = 0;
}

//+------------------------------------------------------------------+
//| Expert transaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    // Debug logging for all transactions
    Print("Transaction type: ", trans.type, 
          ", Order: ", trans.order,
          ", Position: ", trans.position,
          ", Deal: ", trans.deal);
          
    // When a deal is added (order executed)
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        ulong dealTicket = trans.deal;
        if(dealTicket > 0) {
            if(HistoryDealSelect(dealTicket)) {
                ulong orderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                
                // Special handling for Level 1 market order
                if(levels[0].orderTicket == 1 && levels[0].positionTicket == 0) {
                    levels[0].positionTicket = trans.position;
                    levels[0].SetActive(trans.position);
                    Print("Level 1 position ticket set to: ", trans.position);
                    
                    // Now that Level 1 is active, place Level 2 stop order
                    PlacePendingOrder(1, !levels[0].isLong, levels[0].entryPrice);
                }
                
                // Find corresponding level for pending orders that got filled
                for(int i=1; i<5; i++) {  // Start from 1 since Level 1 is handled separately
                    if(levels[i].orderTicket == orderTicket) {
                        Print("Level ", i+1, " Deal - Price: ", dealPrice, 
                              " Type: ", (dealType == DEAL_TYPE_BUY ? "Buy" : "Sell"));
                              
                        // If position opened from pending order
                        if(dealEntry == DEAL_ENTRY_IN) {
                            levels[i].SetActive(trans.position);
                            Print("Level ", i+1, " activated - Position ticket: ", trans.position);
                            
                            // Check if this is Level 5
                            if(i == 4) {
                                HandleExit("Maximum Level (5) Reached");
                            }
                            // Only place next level's order when current level becomes active
                            else if(i < 4) {
                                Print("Level ", i+1, " Activated - Setting up Level ", i+2);
                                PlacePendingOrder(i+1, !levels[i].isLong, levels[i].entryPrice);
                            }
                        }
                        break;
                    }
                }
            }
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
        if(levels[i].orderTicket > 0 && levels[i].state != STATE_ACTIVE) {
            trade.OrderDelete(levels[i].orderTicket);
            Print("Deleting pending order for Level ", i+1, " (Ticket: ", levels[i].orderTicket, ")");
            levels[i].orderTicket = 0;  // Clear the ticket
        }
    }
    
    Print("Strategy Exit - Reason: ", reason, 
          " - All pending orders deleted, no new orders will be placed");
}

void OnTrade()
{
    // Only check Level 1 for debugging
    if(levels[0].state == STATE_ACTIVE && levels[0].positionTicket > 0) {
        if(!PositionSelectByTicket(levels[0].positionTicket)) {
            Print("L1 OnTrade - Position closed, updating state");
            levels[0].SetClosed(PositionGetDouble(POSITION_PRICE_CURRENT));
            UpdatePriceLabels(0);
        }
    }
}

void CheckExitConditions()
{
    // Check for exit conditions
    for(int i=0; i<5; i++) {
        if(levels[i].orderTicket > 0 || levels[i].state == STATE_ACTIVE) {
            CheckLevelExit(i);
            UpdatePriceLabels(i);
        }
    }
    
    UpdateVisualization();
}

//+------------------------------------------------------------------+
//| Expert timer function                                              |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Only check Level 1 for debugging
    if(levels[0].state != STATE_NONE) {
        // Verify position status
        if(levels[0].state == STATE_ACTIVE && levels[0].positionTicket > 0) {
            if(!PositionSelectByTicket(levels[0].positionTicket)) {
                Print("L1 Timer - Position closed, updating state");
                levels[0].SetClosed(PositionGetDouble(POSITION_PRICE_CURRENT));
                UpdatePriceLabels(0);
            }
        }
    }
}

