eeglab;  % must run once to init plugins

vhdr_path = "D:\CNAP Data\BV Pipeline\VitaSense Validation\Subject_3.vhdr";  % or 'C:\path\to\Bailey.vhdr'

[pth, name, ext] = fileparts(vhdr_path);
vhdr_file = name + ext;               % string-safe concatenation

EEG = pop_loadbv(char(pth), char(vhdr_file));
EEG = eeg_checkset(EEG);


%% Extract signals

labels = {EEG.chanlocs.labels};

ecg_idx  = find(strcmpi(labels, 'ECG'));
spo2_idx = find(strcmpi(labels, 'SPO2'));

ecg  = double(EEG.data(ecg_idx, :));
spo2 = double(EEG.data(spo2_idx, :));

fs = EEG.srate;
t  = (0:length(ecg)-1)/fs;

%% Plot the raw signals 

figure('Color','w');

subplot(2,1,1)
plot(t, ecg, 'k')
xlabel('Time (s)')
ylabel('ECG (uV)')
title('Raw ECG')
grid on

subplot(2,1,2)
plot(t, spo2, 'r')
xlabel('Time (s)')
ylabel('SPO2 channel (uV)')
title('Raw SPO2 / Pleth')
grid on


%% Heart rate 

% --- Extract ECG ---
labels = {EEG.chanlocs.labels};
ecg_idx = find(strcmpi(labels,'ECG'));
ecg = double(EEG.data(ecg_idx,:));
fs = EEG.srate;

% --- Preprocess ECG (R-peak emphasis) ---
ecg_f = bandpass(ecg,[5 20],fs);   % standard R-peak band
ecg_sq = ecg_f.^2;                 % emphasize peaks

% --- Peak detection ---
minPeakDist = round(0.25*fs);      % 250 ms refractory
minPeakProm = 0.5*std(ecg_sq);     % adaptive threshold

[~,locs] = findpeaks(ecg_sq, ...
    'MinPeakDistance',minPeakDist, ...
    'MinPeakProminence',minPeakProm);

% --- Heart rate ---
RR = diff(locs)/fs;        % seconds
HR_inst = 60 ./ RR;        % bpm
HR_mean = mean(HR_inst,'omitnan');

disp(HR_mean)
disp()
