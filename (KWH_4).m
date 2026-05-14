%% MASTER SCRIPT: Energy & Temperature Profile (Exp 4)
% Style: CLEAN (No Title, No Legend) + Dynamic Limits + Table
% COLORS: Automated Viridis Import
clear; clc; close all;

% --- 1. CONFIGURATION & COLORS (Using installed 'viridis') ---
fileNTC = 'TEST_EMPTY_4.txt';
fileKWH = 'KWH_HEAT_UP_EMPTY_4.txt';

% Importiere 5 Abstufungen der Viridis-Palette
try
    cols = viridis(5); 
catch
    error('Das Paket "viridis" wurde nicht gefunden. Bitte via Add-Ons installieren.');
end


c_Energy  = [0, 0, 0];  
c_TempIn  = cols(4,:);  
c_TempOut = cols(5,:);  
c_RefLine = [0.50, 0.50, 0.50];  
t_TargetReached_Min = 25.133; 

% Manuelle Vergleichsdaten (Exp 1-3)
data_Exp1 = [0.055, 2368]; 
data_Exp2 = [0.029, 1499]; 
data_Exp3 = [0.009, 450];  

%% 2. DATA PROCESSING (NTC)
if ~isfile(fileNTC), warning('File missing: %s', fileNTC); return; end
opts = detectImportOptions(fileNTC, 'NumHeaderLines', 0);
try
    fid = fopen(fileNTC, 'r'); rawLines = textscan(fid, '%s', 'Delimiter', '\n'); fclose(fid);
    hIdx = find(contains(rawLines{1}, 'Time_Sec'), 1, 'first');
    opts.VariableNamesLine = hIdx; opts.DataLine = hIdx+1;
    T_NTC = readtable(fileNTC, opts);
catch
    warning('Fehler beim Lesen der NTC Datei.'); return;
end
if iscell(T_NTC.Time_Sec), T_NTC.Time_Sec = str2double(T_NTC.Time_Sec); end
if iscell(T_NTC.T_Innen), T_NTC.T_Innen = str2double(T_NTC.T_Innen); end
if iscell(T_NTC.T_Aussen), T_NTC.T_Aussen = str2double(T_NTC.T_Aussen); end
if iscell(T_NTC.Heizung), T_NTC.Heizung = str2double(T_NTC.Heizung); end
T_NTC = rmmissing(T_NTC);
rawTime = T_NTC.Time_Sec;
corrTime = rawTime; offset = 0;
for k=2:length(rawTime)
    if rawTime(k) < rawTime(k-1), offset = offset + rawTime(k-1); end
    corrTime(k) = rawTime(k) + offset;
end
T_NTC.Time_Abs = corrTime;
idxStart = find(T_NTC.Heizung > 0, 1, 'first');
if isempty(idxStart), t0 = 0; else, t0 = T_NTC.Time_Abs(idxStart); end
time_NTC_Min = (T_NTC.Time_Abs - t0) / 60.0;

%% 3. DATA PROCESSING (KWh)
if ~isfile(fileKWH), warning('File missing: %s', fileKWH); return; end
fid = fopen(fileKWH, 'r');
kwh_data = [];
while ~feof(fid)
    line = fgetl(fid);
    vals = sscanf(line, '%f,%f'); 
    if length(vals) == 2, kwh_data = [kwh_data; vals']; end
end
fclose(fid);
if isempty(kwh_data)
    time_KWh_Min = 0; val_KWh = 0; val_KWh_Smooth = 0;
else
    time_KWh_Min = kwh_data(:,1) / 60.0;
    val_KWh = kwh_data(:,2);
    val_KWh_Smooth = smoothdata(val_KWh, 'gaussian', 10);
end

%% 4. CALCULATIONS
[~, idxCut] = min(abs(time_KWh_Min - t_TargetReached_Min));
if isempty(idxCut), energy_HeatUp = 0; else, energy_HeatUp = val_KWh(idxCut); end
% Holding Power Calc
t_Hold_Min = time_KWh_Min(idxCut:end);
e_Hold_kWh = val_KWh(idxCut:end);
if length(t_Hold_Min) > 5
    t_Hold_Hours = (t_Hold_Min - t_Hold_Min(1)) / 60.0;
    e_Hold_Delta = e_Hold_kWh - e_Hold_kWh(1);
    p = polyfit(t_Hold_Hours, e_Hold_Delta, 1);
    power_Hold_Exp4 = p(1); 
else
    power_Hold_Exp4 = NaN;
end
% Exp 1-3 Power
P1 = data_Exp1(1) / (data_Exp1(2)/3600);
P2 = data_Exp2(1) / (data_Exp2(2)/3600);
P3 = data_Exp3(1) / (data_Exp3(2)/3600);
all_Hold_Powers = [P1, P2, P3, power_Hold_Exp4];

%% 5. PLOTTING (CLEAN & DYNAMIC)
fig = figure('Color', 'w', 'Position', [100, 100, 900, 600]);

% --- AXIS SETUP ---
yyaxis left
ax = gca; 

% -- Left Axis: Temperature (Viridis Index 2) --
set(ax, 'YColor', c_TempIn, 'FontName', 'Arial', 'FontSize', 16, 'LineWidth', 1.2, 'TickDir', 'out');
hold on;
mask = time_NTC_Min > -1.5; 

% Plot Temp Innen
plot(time_NTC_Min(mask), T_NTC.T_Innen(mask), '-', 'Color', c_TempIn, 'LineWidth', 2.5);
% Plot Temp Aussen (Viridis Index 4 - Hellgrün)
plot(time_NTC_Min(mask), T_NTC.T_Aussen(mask), '-', 'Color', c_TempOut, 'LineWidth', 2.0); 

ylabel('Temperature (°C)', 'FontWeight', 'bold');

% DYNAMIC LIMITS TEMP
maxTemp = max([max(T_NTC.T_Innen(mask)), max(T_NTC.T_Aussen(mask))]);
if isempty(maxTemp), maxTemp=80; end
ylim([20, maxTemp + 5]); 

% -- Right Axis: Energy (Viridis Index 1 - Dark Purple) --
yyaxis right
set(ax, 'YColor', c_Energy); 
ylabel('Energy Consumed (kWh)', 'FontWeight', 'bold');
plot(time_KWh_Min, val_KWh_Smooth, '-', 'Color', c_Energy, 'LineWidth', 3);

% DYNAMIC LIMITS ENERGY
maxE = max(val_KWh);
if maxE > 0
    ylim([0, maxE * 1.05]); 
else
    ylim([0, 1]);
end

% -- Reference Line --
xline(t_TargetReached_Min, '--', 'Color', c_RefLine, 'LineWidth', 1.2);

% -- Styling (No Title, No Legend) --
grid on; box off; 
xlabel('Time (min)', 'FontWeight', 'bold');
if max(time_KWh_Min) > 0
    xlim([-1.5, max(time_KWh_Min) + 1]);
end

% Save
exportgraphics(fig, 'Exp4_Energy_Profile_Viridis.pdf', 'ContentType', 'vector');

%% 6. OUTPUT TABLE
fprintf('\n========================================\n');
fprintf(' HEAT LOSS ANALYSIS (HOLDING PHASE)\n');
fprintf(' Power required to maintain ~50°C\n');
fprintf('========================================\n');
fprintf(' Exp 1 (No Insulation):  %6.3f kW\n', P1);
fprintf(' Exp 2 (Partial Iso):    %6.3f kW\n', P2);
fprintf(' Exp 3 (Better Iso):     %6.3f kW\n', P3);
fprintf(' Exp 4 (Full Auto):      %6.3f kW\n', power_Hold_Exp4);
fprintf('----------------------------------------\n');
fprintf(' MEAN POWER LOSS:        %6.3f kW\n', mean(all_Hold_Powers, 'omitnan'));
fprintf('========================================\n');