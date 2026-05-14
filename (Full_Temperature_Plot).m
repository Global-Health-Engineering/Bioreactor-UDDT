%% 50C Analysis
clear; clc; close all;

% Files
dir_data = 'FULL_TEST';
f_ntc    = 'TEST_FULL_50_Composting.txt';
f_bot    = 'Full_Test_Bottom.csv';
f_rnd1   = 'Full_Test_Random_1.csv';
f_rnd2   = 'Full_Test_Random 2.csv';

% Settings
mix_times = [1.5, 4.08, 22.3, 28.13, 46.67, 49.95, 53.67, 59.75];
t_zero = datetime(2026, 1, 26, 09, 36, 00);
resample_min = 5; 

cols = viridis(10);

% Colors
c_bot      = cols(1,:);  
c_r1       = cols(3,:);  
c_r2       = cols(7,:);  
c_ntc_in   = cols(9,:); 
c_ntc_out  = cols(10,:); 
c_mix      = [0.60, 0.60, 0.60];

%% Load NTC
[raw_ntc, dur_ntc] = load_ntc(fullfile(dir_data, f_ntc));
raw_ntc.Hours = raw_ntc.Time_Sec / 3600;

% clean data
raw_ntc.T_Innen(raw_ntc.T_Innen < 0 | raw_ntc.T_Innen > 120) = NaN;
raw_ntc.T_Aussen(raw_ntc.T_Aussen < 0 | raw_ntc.T_Aussen > 120) = NaN;
raw_in  = fillmissing(raw_ntc.T_Innen, 'linear');
raw_out = fillmissing(raw_ntc.T_Aussen, 'linear');

% resample
[unique_hours, idx_uniq] = unique(raw_ntc.Hours);
unique_in  = raw_in(idx_uniq);
unique_out = raw_out(idx_uniq);

t_grid_h = (0 : (resample_min/60) : max(unique_hours))'; 
d_ntc = table();
d_ntc.Hours = t_grid_h;

if length(unique_hours) > 2
    d_ntc.T_In  = interp1(unique_hours, unique_in,  t_grid_h, 'linear');
    d_ntc.T_Out = interp1(unique_hours, unique_out, t_grid_h, 'linear');
else
    d_ntc.T_In = unique_in;
    d_ntc.T_Out = unique_out;
    d_ntc.Hours = unique_hours;
end

%% Load CSV
d_bot = load_csv(fullfile(dir_data, f_bot), t_zero);
d_r1  = load_csv(fullfile(dir_data, f_rnd1), t_zero);
d_r2  = load_csv(fullfile(dir_data, f_rnd2), t_zero);

%% Plot
fig = figure('Color', 'w', 'Position', [50, 50, 1200, 700]);
ax = gca;
hold on;

% mixing lines
for t = mix_times
    xline(t, '--', 'Color', c_mix, 'LineWidth', 1.0, 'Alpha', 0.5, 'HandleVisibility', 'off');
end

% plot lines
p_out = plot(d_ntc.Hours, d_ntc.T_Out, '-', 'Color', c_ntc_out, 'LineWidth', 0.8, 'DisplayName', 'Heater Temp (Control)');
p_in  = plot(d_ntc.Hours, d_ntc.T_In,  '-', 'Color', c_ntc_in,  'LineWidth', 1.2, 'DisplayName', 'Internal Temp (Biomass)');
p_bot = plot(d_bot.Hours, d_bot.Temp, '-', 'Color', c_bot, 'LineWidth', 2.0, 'DisplayName', 'Bottom Sensor');
p_r1  = plot(d_r1.Hours,  d_r1.Temp,  '-', 'Color', c_r1,  'LineWidth', 2.0, 'DisplayName', 'Random 1');
p_r2  = plot(d_r2.Hours,  d_r2.Temp,  '-', 'Color', c_r2,  'LineWidth', 2.0, 'DisplayName', 'Random 2');

grid on; box off;       
xlim([0, dur_ntc]);
ylim([20, 80]); 
xlabel('Time (h)', 'FontSize', 20, 'FontWeight', 'bold');
ylabel('Temperature (°C)', 'FontSize', 20, 'FontWeight', 'bold');

%legend([p_in, p_out, p_bot, p_r1, p_r2], ...
       %{'Internal Temp (Biomass)', 'Heater Temp (Control)', 'Bottom Sensor', 'Random 1', 'Random 2'}, ...
       %'Location', 'eastoutside', 'FontSize', 11);

set(ax, 'FontSize', 19, 'LineWidth', 1.2);
hold off;

fprintf('Total Duration: %.2f h\n', dur_ntc);

%% Functions
function [T, h_dur] = load_ntc(path)
    if ~isfile(path), error('File missing: %s', path); end
    fid = fopen(path, 'r');
    raw = textscan(fid, '%s', 'Delimiter', '\n'); fclose(fid);
    
    mat = [];
    lines = raw{1};
    for i=1:length(lines)
        l = strtrim(lines{i});
        if isempty(l) || ~isstrprop(l(1),'digit'), continue; end
        try
            v = str2double(strsplit(l, ','));
            if length(v)>=3 && ~isnan(v(1)), mat = [mat; v(1:3)]; end
        catch, continue; end
    end
    
    % fix time resets
    t_raw = mat(:,1);
    t_new = t_raw; offset = 0;
    for k=2:length(t_raw)
        if t_raw(k) < t_raw(k-1)-5, offset = offset + t_raw(k-1); end
        t_new(k) = t_raw(k) + offset;
    end
    
    T = table(t_new, mat(:,2), mat(:,3), 'VariableNames', {'Time_Sec','T_Innen','T_Aussen'});
    h_dur = max(t_new)/3600;
end

function T = load_csv(path, t_0)
    if ~isfile(path), error('File missing: %s', path); end
    opts = detectImportOptions(path);
    opts.VariableNamingRule = 'preserve';
    raw = readtable(path, opts);
    
    rd = raw{:,1};
    if isdatetime(rd), d = rd; else
        try d = datetime(rd, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
        catch, d = datetime(rd); end
    end
    
    idx = contains(raw.Properties.VariableNames, 'Temp');
    v_temp = raw{:, idx};
    if iscell(v_temp), v_temp = str2double(v_temp); end
    
    T = table(d, v_temp, 'VariableNames', {'Date','Temp'});
    T = T(T.Date >= t_0, :);
    
    if isempty(T)
        T = table([],[],[],'VariableNames',{'Hours','Temp'});
        return;
    end
    
    T.Hours = seconds(T.Date - t_0)/3600;
    
    % clean
    T.Temp(T.Temp < -20 | T.Temp > 120) = NaN;
    T.Temp = fillmissing(T.Temp, 'linear');
end