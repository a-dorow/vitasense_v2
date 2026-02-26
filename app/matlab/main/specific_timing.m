%==========================================================
%  BV (.vhdr) ECG + SPO2 Extraction + HR (0–45 s only)
%  Requires EEGLAB on path + your filter function file:
%     filter_fcn_liu.m
%==========================================================

clc; clear; close all;

eeglab;  % must run once to init plugins

%% ---------------- USER CONFIG ----------------
vhdr_path = "D:\CNAP Data\BV Pipeline\VitaSense Validation\Subject_2.vhdr";

t_start = 0;     % seconds
t_end   = 45;    % seconds (ignore after this)

% Filter settings
hp_cutoff_view = 0.5;   % for viewing/cleaning (optional)
lp_cutoff_view = 35;

hp_cutoff_det  = 5;     % for R-peak emphasis
lp_cutoff_det  = 30;

% Peak detection settings
minPeakDist_sec = 0.25; % 250 ms refractory
prom_scale      = 0.5;  % * std threshold on detection signal

% Post-squaring smoothing (helps suppress spiky noise)
smooth_win_sec  = 0.12; % 120 ms moving average

% Physiologic HR bounds for cleanup
HR_min = 35;
HR_max = 220;

%% ---------------- LOAD BV ----------------
[pth, name, ext] = fileparts(vhdr_path);
vhdr_file = name + ext;

EEG = pop_loadbv(char(pth), char(vhdr_file));
EEG = eeg_checkset(EEG);

labels = {EEG.chanlocs.labels};

% Robust channel finding
ecg_idx  = find(strcmpi(labels, 'ECG'), 1);
spo2_idx = find(strcmpi(labels, 'SPO2'), 1);

if isempty(ecg_idx)
    error("ECG channel not found. Available labels: %s", strjoin(labels, ", "));
end
if isempty(spo2_idx)
    warning("SPO2 channel not found. Available labels: %s", strjoin(labels, ", "));
end

ecg  = double(EEG.data(ecg_idx, :));
fs   = EEG.srate;
t    = (0:length(ecg)-1) / fs;

if ~isempty(spo2_idx)
    spo2 = double(EEG.data(spo2_idx, :));
else
    spo2 = [];
end

%% ---------------- PLOT RAW (FULL) ----------------
figure('Color','w');
subplot(2,1,1)
plot(t, ecg, 'k'); grid on
xlabel('Time (s)'); ylabel('ECG (uV)')
title('Raw ECG (full recording)')

subplot(2,1,2)
if ~isempty(spo2)
    plot(t, spo2, 'r'); grid on
    ylabel('SPO2 channel (uV)')
    title('Raw SPO2 / Pleth (full recording)')
else
    text(0.1,0.5,'SPO2 channel not found','FontSize',12)
    axis off
end
xlabel('Time (s)')

%% ---------------- WINDOW TO 0–45 s ----------------
i1 = max(1, floor(t_start*fs) + 1);
i2 = min(length(ecg), floor(t_end*fs));

ecg_win = ecg(i1:i2);
t_win   = (0:length(ecg_win)-1)/fs + t_start;

%% ---------------- FILTER (VIEW) OPTIONAL ----------------
% If you want a cleaner-looking ECG for inspection
ecg_view = filter_fcn_liu(ecg_win, fs, hp_cutoff_view, lp_cutoff_view);

figure('Color','w');
plot(t_win, ecg_view); grid on
title(sprintf('ECG (0–%.1f s)', t_end, hp_cutoff_view, lp_cutoff_view))
xlabel('Time (s)');
ylabel('ECG (uV)')

%% ---------------- FILTER (DETECTION) + HR ----------------
ecg_det = filter_fcn_liu(ecg_win, fs, hp_cutoff_det, lp_cutoff_det);

% Square to emphasize R-peaks
ecg_sq = ecg_det.^2;

% Smooth squared signal to reduce spiky noise
smooth_win = max(1, round(smooth_win_sec * fs));
ecg_sq_s = movmean(ecg_sq, smooth_win);

% Peak detection
minPeakDist = max(1, round(minPeakDist_sec * fs));
minPeakProm = prom_scale * std(ecg_sq_s);

[pks, locs] = findpeaks(ecg_sq_s, ...
    'MinPeakDistance', minPeakDist, ...
    'MinPeakProminence', minPeakProm);

% Sanity check + HR computation
if numel(locs) < 3
    warning("Too few peaks found in 0–%.1f s. HR estimate unreliable.", t_end);
    HR_mean = NaN;
    HR_inst = [];
else
    RR = diff(locs) / fs;          % seconds
    HR_inst = 60 ./ RR;            % bpm

    % Remove physiologically impossible beats
    HR_inst = HR_inst(HR_inst >= HR_min & HR_inst <= HR_max);

    HR_mean = mean(HR_inst, 'omitnan');
end

%% ---------------- VISUALIZE DETECTION ----------------
figure('Color','w');

subplot(3,1,1)
plot(t_win, ecg_det); grid on
title(sprintf('Detection ECG (0–%.1f s) | notch + [%.1f–%.1f] Hz', t_end, hp_cutoff_det, lp_cutoff_det))
xlabel('Time (s)'); ylabel('uV')

subplot(3,1,2)
plot(t_win, ecg_sq, 'k'); grid on
title('Squared ECG (for peak emphasis)')
xlabel('Time (s)'); ylabel('uV^2')

subplot(3,1,3)
plot(t_win, ecg_sq_s, 'k'); hold on; grid on
if ~isempty(locs)
    plot(t_win(locs), ecg_sq_s(locs), 'ro', 'MarkerSize', 4);
end
title(sprintf('Smoothed Squared ECG + Peaks | Peaks=%d | HR=%.1f bpm', numel(locs), HR_mean))
xlabel('Time (s)'); ylabel('uV^2')

%% ---------------- OUTPUT ----------------
fprintf('\nSubject file: %s\n', vhdr_path);
fprintf('Sampling rate (fs): %.2f Hz\n', fs);
fprintf('Window used: %.1f–%.1f s\n', t_start, t_end);
fprintf('Detected peaks: %d\n', numel(locs));
fprintf('Mean HR (0–%.1f s): %.2f bpm\n\n', t_end, HR_mean);
