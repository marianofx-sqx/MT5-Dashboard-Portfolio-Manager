//+------------------------------------------------------------------+
//|                                     Dashboard_Portfolio_Manager.mq5 |
//|                                  Copyright 2025, Mariano Santa Cruz |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Mariano Santa Cruz"
#property link      ""
#property version   "1.00"
#property description "DASHBOARD PROFESIONAL DE AUDITORÍA ALGORÍTMICA"
#property description " "
#property description "Herramienta de control para gestión de múltiples estrategias:"
#property description "1. Identificación Inteligente: Detecta nombres vía CustomComment (filtra etiquetas de broker)."
#property description "2. Métricas Institucionales: Profit Factor, R/B Ratio, Win Rate, Avg Win/Loss."
#property description "3. Gestión de Riesgo: Alertas visuales por racha de pérdidas y drawdowns críticos."
#property description "4. Big Data: Exportación de historial detallado a CSV para análisis de Equity Curves."
#property description "5. UX: Interfaz redimensionable, ordenable y con filtros temporales."

//--- INPUTS: CONFIGURACIÓN VISUAL
input group "Configuración Visual"
input int InpPanelWidth  = 1200; // Ancho del Panel (px)
input int InpPanelHeight = 300;  // Alto del Panel (px)
input int InpFontSize    = 10;   // Tamaño de Fuente

//--- INPUTS: GESTIÓN DE RIESGO
input group "Gestión de Riesgo (Alarmas)"
input double InpLossAlertLevel = -100.0; // Alerta: Pérdida monetaria mayor a ($)
input int    InpMaxConsecutiveLosses = 5; // Alerta: Racha de pérdidas consecutivas
input int    InpMinTradesForAlert = 10;   // Alerta CRÍTICA: Profit negativo tras N trades

//--- INPUTS: DATOS
input group "Configuración de Datos"
input int InpUpdateIntervalSecs = 10; // Refresco de datos (segundos)

//--- CONSTANTES DE DISEÑO
#define FONT_FACE "Calibri"
#define CHART_OBJ_PREFIX "DASH_PF_MGR_" 
#define HEADER_HEIGHT 40
#define ROW_HEIGHT 20
#define START_X 15
#define START_Y 15
#define SCROLL_WIDTH 20

//--- PALETA DE COLORES
#define COLOR_BG C'28,28,28'
#define COLOR_HEADER C'45,45,45'
#define COLOR_ROW_DARK C'35,35,35'
#define COLOR_ROW_LIGHT C'40,40,40'
#define COLOR_TOTAL_ROW C'15,15,15'
#define COLOR_TEXT_HEADER C'210,210,210'
#define COLOR_TEXT_DATA C'230,230,230'
#define COLOR_PROFIT C'30,200,100'
#define COLOR_LOSS C'255,80,80'
#define COLOR_ALERT C'255,69,0'        // Naranja (Advertencia)
#define COLOR_CRITICAL_BG C'180,0,0'   // Rojo Oscuro (Fondo Crítico)
#define COLOR_CRITICAL_TXT C'255,255,255' 
#define COLOR_BUTTON C'60,60,60'
#define COLOR_EXPORT_BTN C'0,130,220'
#define COLOR_PERIOD_BTN C'50,50,50'
#define COLOR_PERIOD_BTN_ACTIVE C'0,150,255'

//--- ENUMERACIONES
enum ENUM_SORT_COLUMN 
{ 
   SORT_BY_MAGIC, SORT_BY_STRATEGY, SORT_BY_SYMBOL, SORT_BY_PROFIT, 
   SORT_BY_PROFIT_FACTOR, SORT_BY_TRADES, SORT_BY_WINRATE, 
   SORT_BY_AVG_WIN, SORT_BY_AVG_LOSS, SORT_BY_RR_RATIO 
};

enum ENUM_PERIOD 
{ 
   PERIOD_7D, PERIOD_30D, PERIOD_YTD, PERIOD_ALL 
};

//--- ESTRUCTURAS DE DATOS
struct TradeInfo 
{ 
   ulong ticket; datetime time; ulong magic; string symbol; string comment; 
   double profit; long type; double volume; double price; double commission; double swap; double fee; 
};

struct MagicStats 
{ 
   ulong magic_number; string strategy_name; string symbol; 
   double total_profit; int total_trades; int winning_trades; 
   double gross_profit; double gross_loss; 
   int current_consecutive_losses; 
};

struct NameMemory { ulong magic; string name; };

//--- VARIABLES GLOBALES
MagicStats G_stats_array[];
TradeInfo G_all_trades[];
NameMemory G_name_memory[];
ENUM_SORT_COLUMN G_current_sort_column = SORT_BY_PROFIT;
bool G_sort_ascending = false;
int G_scroll_position = 0;
ENUM_PERIOD G_current_period = PERIOD_30D;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1);
   CollectAllHistoryTrades();
   DrawDashboard();
   EventSetTimer(InpUpdateIntervalSecs);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 0);
   EventKillTimer();
   ObjectsDeleteAll(0, CHART_OBJ_PREFIX);
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   CollectAllHistoryTrades();
   DrawDashboard();
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &l, const double &d, const string &s)
{
   if(id == CHARTEVENT_CHART_CHANGE) DrawDashboard();
   if(id == CHARTEVENT_CLICK)
   {
      int x = (int)l;
      int y = (int)d;
      HandleHeaderClicks(x, y);
      HandleScrollClicks(x, y);
      HandleButtonClicks(x, y);
   }
}

//+------------------------------------------------------------------+
//| LOGICA DE INTERFAZ: MANEJADORES DE CLICS                         |
//+------------------------------------------------------------------+
void HandleHeaderClicks(int x, int y)
{
    int header_y_start = START_Y + HEADER_HEIGHT;
    int header_y_end = header_y_start + ROW_HEIGHT;
    if (y < header_y_start || y > header_y_end) return;
    
    int current_x = START_X;
    // Zonas de clic proporcionales
    if (x > current_x && x < current_x + 80) HandleSortClick(SORT_BY_MAGIC); current_x += 80;
    if (x > current_x && x < current_x + 300) HandleSortClick(SORT_BY_STRATEGY); current_x += 300;
    if (x > current_x && x < current_x + 80) HandleSortClick(SORT_BY_SYMBOL); current_x += 80;
    if (x > current_x && x < current_x + 100) HandleSortClick(SORT_BY_PROFIT); current_x += 100;
    if (x > current_x && x < current_x + 100) HandleSortClick(SORT_BY_PROFIT_FACTOR); current_x += 100;
    if (x > current_x && x < current_x + 80) HandleSortClick(SORT_BY_TRADES); current_x += 80;
    if (x > current_x && x < current_x + 80) HandleSortClick(SORT_BY_WINRATE); current_x += 80;
    if (x > current_x && x < current_x + 90) HandleSortClick(SORT_BY_AVG_WIN); current_x += 90;
    if (x > current_x && x < current_x + 90) HandleSortClick(SORT_BY_AVG_LOSS); current_x += 90;
    if (x > current_x && x < current_x + 80) HandleSortClick(SORT_BY_RR_RATIO);
}

void HandleScrollClicks(int x, int y)
{
    int total_rows = ArraySize(G_stats_array);
    int visible_rows = (InpPanelHeight - HEADER_HEIGHT - ROW_HEIGHT * 2) / ROW_HEIGHT;
    if (total_rows <= visible_rows) return;
    
    int scroll_x_start = START_X + InpPanelWidth; 
    int scroll_x_end = scroll_x_start + SCROLL_WIDTH;
    if (x < scroll_x_start || x > scroll_x_end) return;
    
    if (y > START_Y && y < START_Y + SCROLL_WIDTH) 
    { 
        if (G_scroll_position > 0) G_scroll_position--; 
        DrawDashboard(); 
    }
    if (y > START_Y + InpPanelHeight - SCROLL_WIDTH && y < START_Y + InpPanelHeight) 
    { 
        if (G_scroll_position < total_rows - visible_rows) G_scroll_position++; 
        DrawDashboard(); 
    }
}

void HandleButtonClicks(int x, int y)
{
    int btn_y_start = START_Y + (HEADER_HEIGHT / 2) - 11;
    int btn_y_end = btn_y_start + 22;
    if (y > btn_y_start && y < btn_y_end)
    {
        // Botones Exportación
        if (x > START_X + InpPanelWidth - 200 && x < START_X + InpPanelWidth - 105) ExportSummaryToCSV();
        if (x > START_X + InpPanelWidth - 100 && x < START_X + InpPanelWidth - 5) ExportHistoryToCSV();
        
        // Botones Período
        int current_x = START_X + 15;
        if(x > current_x && x < current_x+30) { G_current_period=PERIOD_7D; G_scroll_position=0; DrawDashboard(); } current_x+=35;
        if(x > current_x && x < current_x+30) { G_current_period=PERIOD_30D; G_scroll_position=0; DrawDashboard(); } current_x+=35;
        if(x > current_x && x < current_x+30) { G_current_period=PERIOD_YTD; G_scroll_position=0; DrawDashboard(); } current_x+=35;
        if(x > current_x && x < current_x+30) { G_current_period=PERIOD_ALL; G_scroll_position=0; DrawDashboard(); }
    }
}

void HandleSortClick(ENUM_SORT_COLUMN c)
{
   if(c == G_current_sort_column) G_sort_ascending = !G_sort_ascending;
   else 
   {
      G_current_sort_column = c; 
      G_sort_ascending = (c == SORT_BY_SYMBOL || c == SORT_BY_MAGIC || c == SORT_BY_STRATEGY);
   }
   G_scroll_position = 0;
   DrawDashboard();
}

//+------------------------------------------------------------------+
//| LOGICA DE INTERFAZ: DIBUJADO PRINCIPAL                           |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   ObjectsDeleteAll(0, CHART_OBJ_PREFIX);
   ProcessTradesForCurrentPeriod();
   SortStatsArray();
   
   // Fondo y Cabecera
   DrawRectangle("PANEL_BG", START_X, START_Y, InpPanelWidth, InpPanelHeight, COLOR_BG, false);
   DrawRectangle("HEADER_BG", START_X, START_Y, InpPanelWidth, HEADER_HEIGHT, COLOR_HEADER, false);

   int y_center = START_Y + (HEADER_HEIGHT / 2);
   
   // Botones de Período
   int x_btn = START_X + 15;
   DrawPeriodButton("7D",  x_btn, y_center, PERIOD_7D); x_btn+=35;
   DrawPeriodButton("30D", x_btn, y_center, PERIOD_30D); x_btn+=35;
   DrawPeriodButton("YTD", x_btn, y_center, PERIOD_YTD); x_btn+=35;
   DrawPeriodButton("ALL", x_btn, y_center, PERIOD_ALL);
   
   // Botones de Exportación (Alineados derecha)
   DrawRectangle("EXPORT_SUM_BTN", START_X + InpPanelWidth - 200, y_center-11, 95, 22, COLOR_EXPORT_BTN, false);
   DrawText("EXPORT_SUM_TEXT", START_X + InpPanelWidth - 195, y_center-4, "CSV Resumen", COLOR_TEXT_HEADER, InpFontSize-1);
   DrawRectangle("EXPORT_HIST_BTN", START_X + InpPanelWidth - 100, y_center-11, 95, 22, COLOR_BUTTON, false);
   DrawText("EXPORT_HIST_TEXT", START_X + InpPanelWidth - 95, y_center-4, "CSV Historial", COLOR_TEXT_HEADER, InpFontSize-1);

   // Títulos de Columnas
   int y = START_Y + HEADER_HEIGHT + 10;
   int x = START_X + 10;
   
   DrawColumnHeader("Magic#", x, y, SORT_BY_MAGIC); x += 80;
   DrawColumnHeader("Estrategia", x, y, SORT_BY_STRATEGY); x += 300;
   DrawColumnHeader("Symbol", x, y, SORT_BY_SYMBOL); x += 80;
   DrawColumnHeader("Profit/Loss", x, y, SORT_BY_PROFIT); x += 100;
   DrawColumnHeader("Profit Factor", x, y, SORT_BY_PROFIT_FACTOR); x += 100;
   DrawColumnHeader("Trades", x, y, SORT_BY_TRADES); x += 80;
   DrawColumnHeader("Win Rate", x, y, SORT_BY_WINRATE); x += 80;
   DrawColumnHeader("Avg. Win ($)", x, y, SORT_BY_AVG_WIN); x += 90;
   DrawColumnHeader("Avg. Loss ($)", x, y, SORT_BY_AVG_LOSS); x += 90;
   DrawColumnHeader("Ratio R/B", x, y, SORT_BY_RR_RATIO);

   y += ROW_HEIGHT;
   
   // Fila de Totales
   MagicStats total_stats = CalculateTotalStats();
   DrawDataRow(total_stats, y, -1);
   y += ROW_HEIGHT;
   
   // Filas de Datos (con Scroll)
   int total_rows = ArraySize(G_stats_array);
   int visible_rows = (InpPanelHeight - y + START_Y) / ROW_HEIGHT;
   for(int i = 0; i < visible_rows && (i + G_scroll_position) < total_rows; i++)
   {
      int current_index = i + G_scroll_position;
      DrawDataRow(G_stats_array[current_index], y, current_index);
      y += ROW_HEIGHT;
   }
   
   // Barra de Scroll (si es necesaria)
   if(total_rows > visible_rows)
   {
       int scroll_x = START_X + InpPanelWidth; 
       DrawRectangle("SCROLL_BG", scroll_x, START_Y, SCROLL_WIDTH, InpPanelHeight, COLOR_HEADER, false); 
       DrawRectangle("SCROLL_UP_BTN", scroll_x, START_Y, SCROLL_WIDTH, SCROLL_WIDTH, COLOR_BUTTON, false); 
       DrawText("SCROLL_UP_ARROW", scroll_x + 6, START_Y + 4, "▲", COLOR_TEXT_HEADER); 
       DrawRectangle("SCROLL_DOWN_BTN", scroll_x, START_Y + InpPanelHeight - SCROLL_WIDTH, SCROLL_WIDTH, SCROLL_WIDTH, COLOR_BUTTON, false); 
       DrawText("SCROLL_DOWN_ARROW", scroll_x + 6, START_Y + InpPanelHeight - SCROLL_WIDTH + 4, "▼", COLOR_TEXT_HEADER);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| FUNCIONES DE AYUDA VISUAL                                        |
//+------------------------------------------------------------------+
void DrawPeriodButton(string text, int x, int y, ENUM_PERIOD period)
{
   color c = (period == G_current_period) ? COLOR_PERIOD_BTN_ACTIVE : COLOR_PERIOD_BTN;
   DrawRectangle("BTN_"+text, x-5, y-10, 30, 18, c, false);
   DrawText("BTN_TEXT_"+text, x, y-3, text, COLOR_TEXT_HEADER, InpFontSize-1);
}

void DrawDataRow(const MagicStats &stats, int y, int index)
{
    string id = (index == -1) ? "TOTAL" : (string)stats.magic_number; 
    color r_c = (index == -1) ? COLOR_TOTAL_ROW : ((index%2==0) ? COLOR_ROW_DARK : COLOR_ROW_LIGHT); 
    DrawRectangle("ROW_BG_"+id, START_X, y-5, InpPanelWidth, ROW_HEIGHT, r_c, false);
    
    string m_s = (index == -1) ? "TOTAL" : (string)stats.magic_number; 
    string s_s = (index == -1) ? (string)ArraySize(G_stats_array) + " bots" : stats.strategy_name; 
    string sy_s = (index == -1) ? "Varios" : stats.symbol;
    
    // Fix Label
    if(s_s == "" || s_s == "_") s_s = " ";

    // Lógica de Alarmas
    color name_color = COLOR_TEXT_DATA; 
    color profit_color = (stats.total_profit >= 0) ? COLOR_PROFIT : COLOR_LOSS;
    color trades_color = COLOR_TEXT_DATA;
    color profit_bg_color = r_c;

    if(index != -1)
    {
        if(stats.total_profit < InpLossAlertLevel) { profit_color = COLOR_ALERT; name_color = COLOR_ALERT; }
        if(stats.current_consecutive_losses >= InpMaxConsecutiveLosses) { trades_color = COLOR_ALERT; }
        // Alarma Crítica (Fondo Rojo)
        if(stats.total_trades >= InpMinTradesForAlert && stats.total_profit <= 0)
        {
            profit_bg_color = COLOR_CRITICAL_BG; 
            profit_color = COLOR_CRITICAL_TXT; 
            DrawRectangle("ALARM_BG_"+id, START_X + 470, y-5, 100, ROW_HEIGHT, profit_bg_color, false);
        }
    }

    // Formateo de métricas
    string pf_s; color pf_c; double pf_v=CalculateProfitFactor(stats); 
    if(pf_v<0){pf_s="inf.";pf_c=COLOR_PROFIT;} else {pf_s=DoubleToString(pf_v,2);pf_c=(pf_v>=1.0)?COLOR_PROFIT:COLOR_LOSS;}
    
    double wr=CalculateWinRate(stats); 
    double aw=CalculateAvgWin(stats); 
    double al=CalculateAvgLoss(stats);
    
    string rr_s; color rr_c; double rr_v=CalculateRRRatio(stats); 
    if(rr_v<0){rr_s="inf.";rr_c=COLOR_PROFIT;} else {rr_s=DoubleToString(rr_v,2);rr_c=(rr_v>=1.0)?COLOR_PROFIT:COLOR_LOSS;}
    
    color p_c_final = (index != -1 && stats.total_trades >= InpMinTradesForAlert && stats.total_profit <= 0) ? COLOR_CRITICAL_TXT : profit_color;
    
    int x = START_X + 10;
    DrawText("D_MAGIC_"+id,x,y,m_s,COLOR_TEXT_DATA);x+=80;
    DrawText("D_STRAT_"+id,x,y,s_s,name_color);x+=300; 
    DrawText("D_SYMBOL_"+id,x,y,sy_s,COLOR_TEXT_DATA);x+=80;
    DrawText("D_PROFIT_"+id,x,y,DoubleToString(stats.total_profit,2),p_c_final);x+=100;
    DrawText("D_PF_"+id,x,y,pf_s,pf_c);x+=100;
    DrawText("D_TRADES_"+id,x,y,(string)stats.total_trades,trades_color);x+=80;
    DrawText("D_WINRATE_"+id,x,y,DoubleToString(wr,2)+"%",COLOR_TEXT_DATA);x+=80;
    DrawText("D_AVGW_"+id,x,y,DoubleToString(aw,2),COLOR_PROFIT);x+=90;
    DrawText("D_AVGL_"+id,x,y,DoubleToString(al,2),COLOR_LOSS);x+=90;
    DrawText("D_RR_"+id,x,y,rr_s,rr_c);
}

void DrawColumnHeader(string t,int x,int y,ENUM_SORT_COLUMN c)
{
   string dt=t;
   if(c==G_current_sort_column) dt+=G_sort_ascending?" ▲":" ▼";
   DrawText(t,x,y,dt,COLOR_TEXT_HEADER);
}

void DrawRectangle(string n,int x,int y,int w,int h,color c,bool b)
{
   string on=CHART_OBJ_PREFIX+n;
   ObjectCreate(0,on,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,on,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,on,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,on,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,on,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,on,OBJPROP_BGCOLOR,c);
   ObjectSetInteger(0,on,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,on,OBJPROP_BACK,b);
}

void DrawText(string n,int x,int y,string t,color c,int fs=0)
{
   int final_fs = (fs==0) ? InpFontSize : fs; 
   string on=CHART_OBJ_PREFIX+n;
   ObjectCreate(0,on,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,on,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,on,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,on,OBJPROP_TEXT,t);
   ObjectSetInteger(0,on,OBJPROP_COLOR,c);
   ObjectSetInteger(0,on,OBJPROP_FONTSIZE,final_fs);
   ObjectSetString(0,on,OBJPROP_FONT,FONT_FACE);
   ObjectSetInteger(0,on,OBJPROP_BACK,false);
}

//+------------------------------------------------------------------+
//| LOGICA DE DATOS: EXPORTACION CSV                                 |
//+------------------------------------------------------------------+
void ExportSummaryToCSV()
{
    string time_str = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    StringReplace(time_str, ":", "_");
    StringReplace(time_str, ".", "_"); 
    string fn = "Resumen_Dashboard_" + time_str + ".csv";
    
    int f = FileOpen(fn, FILE_WRITE|FILE_CSV, ";"); 
    if(f == INVALID_HANDLE){Alert("Error al crear archivo.");return;}
    
    FileWrite(f,"Magic#","Estrategia","Symbol","Profit/Loss","Profit Factor","Trades","Win Rate","Avg Win ($)","Avg Loss ($)","Ratio R/B");
    
    MagicStats t=CalculateTotalStats();
    string pf_t,rr_t;
    double pf_v_t=CalculateProfitFactor(t);double rr_v_t=CalculateRRRatio(t);
    if(pf_v_t<0)pf_t="inf.";else pf_t=DoubleToString(pf_v_t,2);
    if(rr_v_t<0)rr_t="inf.";else rr_t=DoubleToString(rr_v_t,2);
    
    FileWrite(f,"TOTAL",(string)ArraySize(G_stats_array)+" bots","Varios",DoubleToString(t.total_profit,2),pf_t,(string)t.total_trades,DoubleToString(CalculateWinRate(t),2)+"%",DoubleToString(CalculateAvgWin(t),2),DoubleToString(CalculateAvgLoss(t),2),rr_t);
    
    for(int i=0;i<ArraySize(G_stats_array);i++){
        MagicStats s=G_stats_array[i];
        double pf_v=CalculateProfitFactor(s);string pf_s=(pf_v<0)?"inf.":DoubleToString(pf_v,2);
        double rr_v=CalculateRRRatio(s);string rr_s=(rr_v<0)?"inf.":DoubleToString(rr_v,2);
        FileWrite(f,(string)s.magic_number,s.strategy_name,s.symbol,DoubleToString(s.total_profit,2),pf_s,(string)s.total_trades,DoubleToString(CalculateWinRate(s),2)+"%",DoubleToString(CalculateAvgWin(s),2),DoubleToString(CalculateAvgLoss(s),2),rr_s);
    }
    FileClose(f);
    Alert("Archivo guardado exitosamente.\nLo encontrará en la carpeta 'Files' dentro del directorio de datos de su terminal.");
}

void ExportHistoryToCSV()
{
    string time_str = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    StringReplace(time_str, ":", "_");
    StringReplace(time_str, ".", "_");
    string fn = "Historial_Graficos_" + time_str + ".csv";
    
    int f = FileOpen(fn, FILE_WRITE|FILE_CSV, ";");
    if(f == INVALID_HANDLE){Alert("Error al crear archivo.");return;}
    
    FileWrite(f,"Ticket","DateTime","Magic","Estrategia","Symbol","Type","Volume","Price","Commission","Swap","Fee","Profit","Cumulative Profit");
    
    double cp=0;
    TradeInfo ft[];
    FilterTradesForCurrentPeriod(ft);
    
    for(int i=0;i<ArraySize(ft);i++){
        cp+=ft[i].profit;
        string strat_name = GetNameFromMemory(ft[i].magic);
        if(strat_name == "") strat_name = ft[i].comment;
        
        string type_str = (ft[i].type == DEAL_TYPE_BUY) ? "BUY" : (ft[i].type == DEAL_TYPE_SELL ? "SELL" : (string)ft[i].type);
        
        FileWrite(f,(string)ft[i].ticket,TimeToString(ft[i].time),(string)ft[i].magic,strat_name,ft[i].symbol,type_str,DoubleToString(ft[i].volume, 2),DoubleToString(ft[i].price, 5),DoubleToString(ft[i].commission, 2),DoubleToString(ft[i].swap, 2),DoubleToString(ft[i].fee, 2),DoubleToString(ft[i].profit,2),DoubleToString(cp,2));
    }
    FileClose(f);
    Alert("Archivo guardado exitosamente.\nLo encontrará en la carpeta 'Files' dentro del directorio de datos de su terminal.");
}

//+------------------------------------------------------------------+
//| LOGICA DE DATOS: CALCULOS Y PROCESAMIENTO                        |
//+------------------------------------------------------------------+
double CalculateAvgWin(const MagicStats &s){if(s.winning_trades>0)return s.gross_profit/s.winning_trades;return 0.0;}
double CalculateAvgLoss(const MagicStats &s){int lt=s.total_trades-s.winning_trades;if(lt>0)return s.gross_loss/lt;return 0.0;}
double CalculateRRRatio(const MagicStats &s){double al=CalculateAvgLoss(s);if(al>0){double aw=CalculateAvgWin(s);return aw/al;}if(CalculateAvgWin(s)>0)return -1.0;return 0.0;}
double CalculateProfitFactor(const MagicStats &s){if(s.gross_loss>0)return s.gross_profit/s.gross_loss;if(s.gross_profit>0)return -1.0;return 0.0;}
double CalculateWinRate(const MagicStats &s){if(s.total_trades>0)return(double)s.winning_trades/s.total_trades*100.0;return 0.0;}

MagicStats CalculateTotalStats()
{
    MagicStats t;ZeroMemory(t);t.strategy_name="TOTAL";
    for(int i=0;i<ArraySize(G_stats_array);i++){
        t.total_profit+=G_stats_array[i].total_profit;
        t.total_trades+=G_stats_array[i].total_trades;
        t.winning_trades+=G_stats_array[i].winning_trades;
        t.gross_profit+=G_stats_array[i].gross_profit;
        t.gross_loss+=G_stats_array[i].gross_loss;
    }
    return t;
}

int CalculateCurrentConsecutiveLosses(ulong magic, const TradeInfo &trades[])
{
    int losses = 0;
    for(int i = ArraySize(trades)-1; i >= 0; i--)
    {
        if(trades[i].magic != magic) continue;
        if(trades[i].profit < 0) losses++;
        else if(trades[i].profit >= 0) break;
    }
    return losses;
}

void ProcessTradesForCurrentPeriod()
{
    ArrayFree(G_stats_array); TradeInfo ft[]; FilterTradesForCurrentPeriod(ft);
    for(int i=0; i<ArraySize(ft); i++)
    {
      TradeInfo t=ft[i]; int fi=-1;
      for(int j=0; j<ArraySize(G_stats_array); j++){if(G_stats_array[j].magic_number==t.magic){fi=j; break;}}
      if(fi==-1)
      {
         int ns=ArraySize(G_stats_array)+1; ArrayResize(G_stats_array,ns); fi=ns-1; ZeroMemory(G_stats_array[fi]);
         G_stats_array[fi].magic_number=t.magic; G_stats_array[fi].symbol=t.symbol;
         
         string stored_name = GetNameFromMemory(t.magic);
         if(stored_name != "") { G_stats_array[fi].strategy_name = stored_name; }
         else 
         { 
             string new_name = FindValidStrategyName(t.magic, G_all_trades); 
             if(new_name != "_") SaveNameToMemory(t.magic, new_name); 
             G_stats_array[fi].strategy_name = (new_name == "_") ? " " : new_name; 
         }
      }
      G_stats_array[fi].total_profit+=t.profit; G_stats_array[fi].total_trades++;
      if(t.profit>=0){G_stats_array[fi].winning_trades++;G_stats_array[fi].gross_profit+=t.profit;}else{G_stats_array[fi].gross_loss-=t.profit;}
    }
    
    for(int i=0; i<ArraySize(G_stats_array); i++)
    {
        G_stats_array[i].current_consecutive_losses = CalculateCurrentConsecutiveLosses(G_stats_array[i].magic_number, ft);
    }
}

string GetNameFromMemory(ulong magic){for(int i=0;i<ArraySize(G_name_memory);i++){if(G_name_memory[i].magic==magic)return G_name_memory[i].name;}return "";}
void SaveNameToMemory(ulong magic, string name){if(GetNameFromMemory(magic)!="")return;int s=ArraySize(G_name_memory);ArrayResize(G_name_memory,s+1);G_name_memory[s].magic=magic;G_name_memory[s].name=name;}

string FindValidStrategyName(ulong magic_number, const TradeInfo &trades[])
{
    for(int i=0; i < ArraySize(trades); i++)
    {
        if(trades[i].magic != magic_number) continue;
        string current_comment = trades[i].comment;
        if(StringLen(current_comment) > 0 && StringGetCharacter(current_comment, 0) != '[') return current_comment;
    }
    return "_";
}

void FilterTradesForCurrentPeriod(TradeInfo &trades_out[])
{
    ArrayFree(trades_out); datetime st=0; MqlDateTime dt; TimeCurrent(dt);
    switch(G_current_period){case PERIOD_7D:st=TimeCurrent()-7*86400;break; case PERIOD_30D:st=TimeCurrent()-30*86400;break; case PERIOD_YTD:dt.mon=1;dt.day=1;dt.hour=0;dt.min=0;dt.sec=0;st=StructToTime(dt);break; case PERIOD_ALL:st=0;break;}
    for(int i=0; i<ArraySize(G_all_trades); i++){if(G_all_trades[i].time>=st){int s=ArraySize(trades_out);ArrayResize(trades_out,s+1);trades_out[s]=G_all_trades[i];}}
}

void CollectAllHistoryTrades()
{
   ArrayFree(G_all_trades); if(!HistorySelect(0,TimeCurrent()))return; uint td=HistoryDealsTotal();
   for(uint i=0; i<td; i++)
   {
      ulong tk=HistoryDealGetTicket(i); if(tk==0)continue; long dt=HistoryDealGetInteger(tk,DEAL_ENTRY); if(dt!=DEAL_ENTRY_OUT&&dt!=DEAL_ENTRY_INOUT)continue;
      int s=ArraySize(G_all_trades);ArrayResize(G_all_trades,s+1); 
      G_all_trades[s].ticket = tk; 
      G_all_trades[s].time=(datetime)HistoryDealGetInteger(tk,DEAL_TIME); 
      G_all_trades[s].magic=HistoryDealGetInteger(tk,DEAL_MAGIC); 
      G_all_trades[s].symbol=HistoryDealGetString(tk,DEAL_SYMBOL); 
      G_all_trades[s].comment=HistoryDealGetString(tk,DEAL_COMMENT); 
      G_all_trades[s].profit=HistoryDealGetDouble(tk,DEAL_PROFIT);
      G_all_trades[s].type = HistoryDealGetInteger(tk, DEAL_TYPE);
      G_all_trades[s].volume = HistoryDealGetDouble(tk, DEAL_VOLUME);
      G_all_trades[s].price = HistoryDealGetDouble(tk, DEAL_PRICE);
      G_all_trades[s].commission = HistoryDealGetDouble(tk, DEAL_COMMISSION);
      G_all_trades[s].swap = HistoryDealGetDouble(tk, DEAL_SWAP);
      G_all_trades[s].fee = HistoryDealGetDouble(tk, DEAL_FEE);
   }
}

void SortStatsArray()
{
   int n=ArraySize(G_stats_array); for(int i=0;i<n-1;i++){for(int j=0;j<n-i-1;j++){bool sw=false; switch(G_current_sort_column){
   case SORT_BY_MAGIC:if(G_sort_ascending?(G_stats_array[j].magic_number>G_stats_array[j+1].magic_number):(G_stats_array[j].magic_number<G_stats_array[j+1].magic_number))sw=true;break;
   case SORT_BY_STRATEGY:if(G_sort_ascending?(G_stats_array[j].strategy_name>G_stats_array[j+1].strategy_name):(G_stats_array[j].strategy_name<G_stats_array[j+1].strategy_name))sw=true;break;
   case SORT_BY_SYMBOL:if(G_sort_ascending?(G_stats_array[j].symbol>G_stats_array[j+1].symbol):(G_stats_array[j].symbol<G_stats_array[j+1].symbol))sw=true;break;
   case SORT_BY_PROFIT:if(G_sort_ascending?(G_stats_array[j].total_profit>G_stats_array[j+1].total_profit):(G_stats_array[j].total_profit<G_stats_array[j+1].total_profit))sw=true;break;
   case SORT_BY_TRADES:if(G_sort_ascending?(G_stats_array[j].total_trades>G_stats_array[j+1].total_trades):(G_stats_array[j].total_trades<G_stats_array[j+1].total_trades))sw=true;break;
   case SORT_BY_PROFIT_FACTOR:{double v1=CalculateProfitFactor(G_stats_array[j]);double v2=CalculateProfitFactor(G_stats_array[j+1]);if(G_sort_ascending?(v1>v2):(v1<v2))sw=true;}break;
   case SORT_BY_WINRATE:{double v1=CalculateWinRate(G_stats_array[j]);double v2=CalculateWinRate(G_stats_array[j+1]);if(G_sort_ascending?(v1>v2):(v1<v2))sw=true;}break;
   case SORT_BY_AVG_WIN:{double v1=CalculateAvgWin(G_stats_array[j]);double v2=CalculateAvgWin(G_stats_array[j+1]);if(G_sort_ascending?(v1>v2):(v1<v2))sw=true;}break;
   case SORT_BY_AVG_LOSS:{double v1=CalculateAvgLoss(G_stats_array[j]);double v2=CalculateAvgLoss(G_stats_array[j+1]);if(G_sort_ascending?(v1>v2):(v1<v2))sw=true;}break;
   case SORT_BY_RR_RATIO:{double v1=CalculateRRRatio(G_stats_array[j]);double v2=CalculateRRRatio(G_stats_array[j+1]);if(G_sort_ascending?(v1>v2):(v1<v2))sw=true;}break;}
   if(sw){MagicStats t=G_stats_array[j];G_stats_array[j]=G_stats_array[j+1];G_stats_array[j+1]=t;}}}}
