%% 70C Analysis (Aligned)
% NTC shifted -6 min to match CSV start
clear; clc; close all;

% Files
dir_data = 'FULL_TEST';
f_ntc    = 'TEST_FULL_70_NTC.txt';
f_kwh    = 'KWH_FULL.txt'; 
f_bot    = '70_bottom.csv';
f_rnd1   = '70_random_1.csv';
f_rnd2   = '70_random_2.csv';

% Settings
t_start = datetime(2026, 1, 29, 08, 13, 00);
ntc_offset = 0.1; % shift correction (hours)
mix_times = [0.408, 0.608, 1.608, 3.13, 3.53];

calc_start_min = 50;
energy_total = 0.385;
resample_min = 0.333;

cols = viridis(10);

% Colors
c_bot      = cols(1,:);  
c_r1       = cols(3,:);  
c_r2       = cols(7,:);  
c_ntc_in   = cols(9,:); 
c_ntc_out  = cols(10,:); 
c_mix      = [0.80, 0.80, 0.80];

%% Load NTC
[raw_ntc, ~] = load_ntc(fullfile(dir_data, f_ntc), 3); 
d_ntc_raw = table();
d_ntc_raw.Hours = raw_ntc.Time_Sec / 3600;

% clean & fill
raw_ntc.Val1(raw_ntc.Val1 < 0 | raw_ntc.Val1 > 130) = NaN; 
raw_ntc.Val2(raw_ntc.Val2 < 0 | raw_ntc.Val2 > 130) = NaN;
d_ntc_raw.T_In  = fillmissing(raw_ntc.Val1, 'linear');
d_ntc_raw.T_Out = fillmissing(raw_ntc.Val2, 'linear');

% shift time
d_ntc_raw.Hours = d_ntc_raw.Hours - ntc_offset;
d_ntc_raw = d_ntc_raw(d_ntc_raw.Hours >= 0, :);

% resample
t_grid_h = (0 : (resample_min/60) : max(d_ntc_raw.Hours))'; 
d_ntc = table();
d_ntc.Hours = t_grid_h;
d_ntc.T_In  = interp1(d_ntc_raw.Hours, d_ntc_raw.T_In,  t_grid_h, 'linear');
d_ntc.T_Out = interp1(d_ntc_raw.Hours, d_ntc_raw.T_Out, t_grid_h, 'linear');
dur_ntc = max(d_ntc.Hours);

%% Load CSV
d_bot = load_csv(fullfile(dir_data, f_bot), t_start);
d_r1  = load_csv(fullfile(dir_data, f_rnd1), t_start);
d_r2  = load_csv(fullfile(dir_data, f_rnd2), t_start);

%% Load Energy & Calc
[raw_kwh, ~] = load_ntc(fullfile(dir_data, f_kwh), 2);
d_kwh = table();
d_kwh.Hours = (raw_kwh.Time_Sec / 3600) - ntc_offset;
d_kwh.kWh   = raw_kwh.Val1;
d_kwh = d_kwh(d_kwh.Hours >= 0, :);

avg_watts = NaN;
E_start = NaN;

t_start_h = calc_start_min / 60;
idx_start = find(d_kwh.Hours >= t_start_h, 1, 'first');

if ~isempty(idx_start)
    E_start = d_kwh.kWh(idx_start);
    dt = dur_ntc - d_kwh.Hours(idx_start);
    if dt > 0
        avg_watts = ((energy_total - E_start) / dt) * 1000; 
    end
end

%% Plot
fig = figure('Color', 'w', 'Position', [50, 50, 1200, 700]);
ax = gca;
hold on;

% mixing lines
for t = mix_times
    xline(t, '--', 'Color', c_mix, 'LineWidth', 1.0, 'Alpha', 0.5, 'HandleVisibility', 'off');
end

% plot data
p_out = plot(d_ntc.Hours, d_ntc.T_Out, '-', 'Color', c_ntc_out, 'LineWidth', 0.8, 'DisplayName', 'Heater Temp (Control)');
p_in  = plot(d_ntc.Hours, d_ntc.T_In,  '-', 'Color', c_ntc_in,  'LineWidth', 1.2, 'DisplayName', 'Internal Temp (Biomass)');
p_bot = plot(d_bot.Hours, d_bot.Temp, '-', 'Color', c_bot, 'LineWidth', 2.0, 'DisplayName', 'Bottom Sensor');
p_r1  = plot(d_r1.Hours,  d_r1.Temp,  '-', 'Color', c_r1,  'LineWidth', 2.0, 'DisplayName', 'Random 1');
p_r2  = plot(d_r2.Hours,  d_r2.Temp,  '-', 'Color', c_r2,  'LineWidth', 2.0, 'DisplayName', 'Random 2');

grid on; box off;
xlim([0, dur_ntc]);
ylim([20, 90]);
xlabel('Time (h)', 'FontSize', 20, 'FontWeight', 'bold');
ylabel('Temperature (°C)', 'FontSize', 20, 'FontWeight', 'bold');

%legend([p_in, p_out, p_bot, p_r1, p_r2], ...
       %{'Internal Temp (Biomass)', 'Heater Temp (Control)', 'Bottom Sensor', 'Random 1', 'Random 2'}, ...
       %'Location', 'eastoutside', 'FontSize', 11);

set(ax, 'FontSize', 19, 'LineWidth', 1.2);
hold off;

% Output
fprintf('Offset applied: %.2f h\n', ntc_offset);
fprintf('Total Duration: %.2f h\n', dur_ntc);
fprintf('Energy @ 50min: %.3f kWh\n', E_start);
fprintf('Avg Power:      %.0f W\n', avg_watts);

%% Functions
function [T_out, duration_h] = load_ntc(fpath, cols)
    if ~isfile(fpath), error('File not found: %s', fpath); end
    fid = fopen(fpath, 'r');
    raw = textscan(fid, '%s', 'Delimiter', '\n'); fclose(fid);
    
    mat = [];
    lines = raw{1};
    for i = 1:length(lines)
        l = strtrim(lines{i});
        if isempty(l) || ~isstrprop(l(1), 'digit'), continue; end
        try
            v = str2double(strsplit(l, ','));
            if length(v) >= 2 && ~isnan(v(1))
                if length(v) < 3 && cols == 3, v(3) = NaN; end
                mat = [mat; v(1:cols)];
            end
        catch, continue; end
    end
    
    t_raw = mat(:,1); t_fix = t_raw; offset = 0;
    for k = 2:length(t_raw)
        if t_raw(k) < (t_raw(k-1) - 5), offset = offset + t_raw(k-1); end
        t_fix(k) = t_raw(k) + offset;
    end
    
    if cols == 2
        T_out = table(t_fix, mat(:,2), nan(size(t_fix)), 'VariableNames', {'Time_Sec','Val1','Val2'});
    else
        T_out = table(t_fix, mat(:,2), mat(:,3), 'VariableNames', {'Time_Sec','Val1','Val2'});
    end
    duration_h = max(t_fix) / 3600;
end

function T = load_csv(fpath, t_start)
    if ~isfile(fpath), error('File not found: %s', fpath); end
    opts = detectImportOptions(fpath); opts.VariableNamingRule = 'preserve';
    raw = readtable(fpath, opts);
    
    rd = raw{:,1};
    if isdatetime(rd), d = rd; else
        try d = datetime(rd, 'InputFormat', 'yyyy-MM-dd HH:mm:ss'); catch, d = datetime(rd); end
    end
    
    idx = contains(raw.Properties.VariableNames, 'Temp');
    v = raw{:, idx}; if iscell(v), v = str2double(v); end
    
    T = table(d, v, 'VariableNames', {'Date','Temp'});
    T = T(T.Date >= t_start, :);
    
    if isempty(T)
        T = table([],[],[], 'VariableNames',{'Hours','Temp'});
        return;
    end
    
    T.Hours = seconds(T.Date - t_start) / 3600;
    T.Temp(T.Temp < -20 | T.Temp > 130) = NaN;
    T.Temp = fillmissing(T.Temp, 'linear');
end