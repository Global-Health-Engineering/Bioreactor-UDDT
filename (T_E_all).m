%% MASTER PLOT: Final Version (Analysis & Mean Calculation) - X-Axis in Minutes
clear; clc; close all;

cols = viridis(10);


baseColors = [
    cols(1,:);  % 1. Bottom Sensor (Dark Purple)
    cols(3,:);  % 2. Metal Sheet (Blue/Teal)
    cols(7,:);  % 3. Top Sensor (Green)
    cols(9,:);  % 4. NTC Internal (Light Green)
    cols(10,:);  % 5. NTC Outside (Yellow)
    0.40, 0.40, 0.40   % 6. Fallback (Grey)
];

legendNames = {'Bottom Sensor', 'Metal Sheet (Heater)', 'Top Sensor', 'NTC Internal (Bulk)', 'NTC Outside (Heater)'};

% --- 2. EXPERIMENT CONFIGURATION ---
exps = struct();

% Exp 1 
exps(1).Title = 'Exp 1';
exps(1).Folder = 'TEST_EMPTY_1';
exps(1).StartTime = datetime(2026, 1, 21, 12, 31, 00);
exps(1).FixReset = false;
exps(1).HeatOff = 6568; 
exps(1).YLim = [20, 85];
exps(1).Files = {'barrel bottom_20260121_TEST_EMPTY_1.xlsx', 'barrel random_20260121_TEST_EMPTY_1.csv', 'barrel top_20260121_TEST_EMPTY_1.csv', 'TEST_EMPTY_70_1_clear.txt'};

% Exp 2
exps(2).Title = 'Exp 2';
exps(2).Folder = 'TEST_EMPTY_2';
exps(2).StartTime = datetime(2026, 1, 21, 15, 56, 00);
exps(2).FixReset = true; 
exps(2).HeatOff = 5314; 
exps(2).YLim = [20, 85];
exps(2).Files = {'barrel bottom_20260121_EMPTY_2.csv', 'barrel metal sheet_20260121_EMPTY_2.csv', 'barrel top_20260121_EMPTY_2.csv', 'TEST_EMPTY_2.txt'};

% Exp 3
exps(3).Title = 'Exp 3';
exps(3).Folder = 'TEST_EMPTY_3';
exps(3).StartTime = datetime(2026, 1, 22, 08, 19, 00);
exps(3).FixReset = false;
exps(3).HeatOff = 4600; 
exps(3).YLim = [20, 75];
exps(3).Files = {'barrel bottom_20260122_EMPTY_3.csv', 'barrel metal sheet_20260122_EMPTY_3.csv', 'barrel top_20260122_EMPTY_3.csv', 'TEST_EMPTY_3.txt'};

% Exp 4
exps(4).Title = 'Exp 4';
exps(4).Folder = 'TEST_EMPTY_4';
exps(4).StartTime = datetime(2026, 1, 22, 12, 05, 00);
exps(4).FixReset = false;
exps(4).HeatOff = 5920; 
exps(4).YLim = [20, 75];
exps(4).Files = {'barrel bottom_20260122_ EMPTY_4.csv', 'barrel metal sheet_20260122_EMPTY_4.csv', 'barrel top_20260122_EMPTY_4.csv', 'TEST_EMPTY_4.txt'};

%% 3. PROCESSING & PLOTTING
fig = figure('Color', 'w', 'Name', 'Combined Analysis', 'Position', [100, 100, 900, 700]);
t = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- CHANGE: X-Axis Label to Minutes ---
xlabel(t, 'Time (min)', 'FontSize', 12, 'FontWeight', 'bold', 'FontName', 'Arial');
ylabel(t, 'Temperature (°C)', 'FontSize', 12, 'FontWeight', 'bold', 'FontName', 'Arial');

coolingResults = {};

for k = 1:4
    ax = nexttile;
    hold on; 
    set(ax, 'Box', 'off', 'TickDir', 'out', 'FontName', 'Arial', 'LineWidth', 1);
    grid on;
    title(exps(k).Title, 'FontSize', 12, 'FontWeight', 'bold', 'FontName', 'Arial');
    
    folder = exps(k).Folder;
    fileList = exps(k).Files;
    tStart = exps(k).StartTime;
    doFix = exps(k).FixReset;
    tOff = exps(k).HeatOff;
    
    plotIdx = 1;
    
    for i = 1:length(fileList)
        fName = fileList{i};
        fullPath = fullfile(folder, fName);
        if ~isfile(fullPath), fullPath = fName; end 
        if ~isfile(fullPath), continue; end
        
        [~, ~, ext] = fileparts(fullPath);
        timeSec = []; tempVal = []; label = '';
        
        % --- LOAD RUUVI (CSV/XLSX) ---
        if strcmpi(ext, '.csv') || strcmpi(ext, '.xlsx')
            try
                opts = detectImportOptions(fullPath); opts.VariableNamingRule = 'preserve';
                try, T = readtable(fullPath, opts); catch, opts = detectImportOptions(fullPath, 'NumHeaderLines', 0); T = readtable(fullPath, opts); end
                rawDate = T{:,1};
                try, if isdatetime(rawDate), T.Datum = rawDate; else, try, T.Datum = datetime(rawDate, 'InputFormat', 'yyyy-MM-dd HH:mm:ss'); catch, T.Datum = datetime(rawDate); end; end; catch, continue; end
                
                if ismember('Datum', T.Properties.VariableNames)
                    T.TimeSec = seconds(T.Datum - tStart);
                    T = T(T.TimeSec >= 0, :);
                    idx = find(contains(T.Properties.VariableNames, 'Temperatur') | contains(T.Properties.VariableNames, 'Temp'), 1);
                    if ~isempty(idx)
                        timeSec = T.TimeSec; rawTemp = T{:, idx};
                        if iscell(rawTemp) || isstring(rawTemp), tempVal = str2double(rawTemp); else, tempVal = double(rawTemp); end
                        if plotIdx <= length(legendNames), label = legendNames{plotIdx}; else, label = 'Unknown'; end
                    end
                end
            catch, continue; end
        end
        % --- LOAD ESP32 (TXT) ---
        if strcmpi(ext, '.txt')
            try
                fid = fopen(fullPath, 'r'); rawLines = textscan(fid, '%s', 'Delimiter', '\n'); fclose(fid);
                hIdx = find(contains(rawLines{1}, 'Time_Sec'), 1, 'first');
                if ~isempty(hIdx)
                    opts = detectImportOptions(fullPath, 'NumHeaderLines', hIdx); opts.VariableNamesLine = hIdx; opts.Delimiter = ',';
                    T = readtable(fullPath, opts);
                    if iscell(T.Time_Sec), T.Time_Sec = str2double(T.Time_Sec); end
                    if iscell(T.T_Innen), T.T_Innen = str2double(T.T_Innen); end
                    if iscell(T.T_Aussen), T.T_Aussen = str2double(T.T_Aussen); end
                    T = rmmissing(T);
                    rawTime = T.Time_Sec;
                    if doFix && length(rawTime) > 1
                        corrTime = rawTime; offset = 0;
                        for z = 2:length(rawTime)
                            if rawTime(z) < rawTime(z-1), offset = offset + rawTime(z-1); end
                            corrTime(z) = rawTime(z) + offset;
                        end
                        timeSecESP = corrTime;
                    else, timeSecESP = rawTime; end
                    
                    if ~isempty(T.T_Innen)
                        % --- CHANGE: Plot divide by 60 for minutes ---
                        plot(timeSecESP / 60.0, T.T_Innen, 'Color', baseColors(4,:), 'LineWidth', 1.2);
                        % Calculation stays in seconds to maintain logic inside function
                        [rate, r2] = calcCooling(timeSecESP, T.T_Innen, tOff);
                        coolingResults(end+1,:) = {exps(k).Title, 'NTC Internal (Bulk)', rate, r2}; 
                    end
                    if ~isempty(T.T_Aussen)
                        % --- CHANGE: Plot divide by 60 for minutes ---
                        plot(timeSecESP / 60.0, T.T_Aussen, 'Color', baseColors(5,:), 'LineWidth', 1.2);
                        [rate, r2] = calcCooling(timeSecESP, T.T_Aussen, tOff);
                        coolingResults(end+1,:) = {exps(k).Title, 'NTC Outside (Heater)', rate, r2}; 
                    end
                    timeSec = [];
                end
            catch, continue; end
        end
        
        % --- PLOT RUUVI & CALC SLOPE ---
        if ~isempty(timeSec) && ~isempty(tempVal) && length(timeSec) == length(tempVal)
             cIdx = mod(plotIdx-1, 3) + 1; 
             % --- CHANGE: Plot divide by 60 for minutes ---
             plot(timeSec / 60.0, tempVal, 'Color', baseColors(cIdx,:), 'LineWidth', 1.2);
             
             % Calculate Cooling Rate (input seconds)
             sensorName = legendNames{cIdx};
             [rate, r2] = calcCooling(timeSec, tempVal, tOff);
             coolingResults(end+1,:) = {exps(k).Title, sensorName, rate, r2};
             
             plotIdx = plotIdx + 1;
        end
    end
    
    if ~isnan(tOff)
        % --- CHANGE: Line divide by 60 for minutes ---
        xline(tOff / 60.0, '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 1.0);
    end
    xlim([0, inf]); ylim(exps(k).YLim);
    if k == 1 || k == 2, xticklabels({}); end 
    if k == 2 || k == 4, yticklabels({}); end 
end

% Save High-Res PDF
exportgraphics(fig, 'Baseline_Heating_four_times.pdf', 'ContentType', 'vector');

%% 4. OUTPUT TABLES (With Mean Calculation)
targetSensors = {'Bottom Sensor', 'Top Sensor', 'Metal Sheet (Heater)', 'NTC Internal (Bulk)'};
for s = 1:length(targetSensors)
    currentSensor = targetSensors{s};
    
    fprintf('\nTABLE %d: %s\n', s, currentSensor);
    fprintf('--------------------------------------------------\n');
    fprintf('%-10s | %-15s | %-6s\n', 'Exp', 'Rate (°C/min)', 'R^2');
    fprintf('-----------|-----------------|-------\n');
    
    ratesForMean = []; % Collector for average
    
    for k = 1:4
        expName = exps(k).Title;
        % Exp 1 Exception for Metal Sheet
        if k == 1 && contains(currentSensor, 'Metal Sheet')
            fprintf('%-10s | %-15s | %-6s\n', expName, '-', '-');
            continue;
        end
        
        idx = -1;
        for r = 1:size(coolingResults, 1)
            if strcmp(coolingResults{r,1}, expName) && contains(coolingResults{r,2}, currentSensor)
                idx = r; break;
            end
        end
        
        if idx ~= -1
            rate = coolingResults{idx,3};
            r2 = coolingResults{idx,4};
            if ~isnan(rate)
                 fprintf('%-10s | %10.4f      | %0.2f\n', expName, rate, r2);
                 ratesForMean(end+1) = rate;
            else
                 fprintf('%-10s | %-15s | %-6s\n', expName, 'N/A', '-');
            end
        else
            fprintf('%-10s | %-15s | %-6s\n', expName, 'N/A', 'N/A');
        end
    end
    
    fprintf('-----------|-----------------|-------\n');
    if ~isempty(ratesForMean)
        fprintf('%-10s | %10.4f      | %s\n', 'MEAN', mean(ratesForMean), '-');
    else
        fprintf('%-10s | %-15s | %s\n', 'MEAN', '-', '-');
    end
    fprintf('--------------------------------------------------\n');
end

%% --- HELPER FUNCTION ---
function [rate, r2] = calcCooling(t, y, tOff)
    rate = NaN; r2 = NaN;
    if isnan(tOff), return; end
    
    mask = t > tOff;
    t_cool = t(mask); y_cool = y(mask);
    if length(t_cool) < 10, return; end 
    [~, maxIdx] = max(y_cool);
    
    t_fit = t_cool(maxIdx:end); y_fit = y_cool(maxIdx:end);
    if length(t_fit) < 5, t_fit = t_cool; y_fit = y_cool; end
    
    % Internal conversion from seconds to minutes for rate calculation
    p = polyfit(t_fit/60, y_fit, 1);
    rate = p(1);
    yfit = polyval(p, t_fit/60);
    yresid = y_fit - yfit;
    SSresid = sum(yresid.^2);
    SStotal = (length(y_fit)-1) * var(y_fit);
    r2 = 1 - SSresid/SStotal;
end