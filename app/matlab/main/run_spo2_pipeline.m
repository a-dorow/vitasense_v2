%% Converting a .mp4 to .avi

video = "D:\CNAP Data\BV Pipeline\VitaSense Validation\Subject_8.mp4";

readerobj = VideoReader(video);
writerobj = VideoWriter("D:\CNAP Data\BV Pipeline\VitaSense Validation\Subject_8.avi", 'Uncompressed AVI');
open(writerobj)

%Loop through the frames
while hasFrame(readerobj)
    frame = readFrame(readerobj);
    writeVideo(writerobj,frame)
end

%Close the writer
close(writerobj)
disp('Conversion Done!')

%%

video_path   = "C:\Users\avask\OneDrive\Desktop\Initial Blood Pressure Testing\subject_1\subject_1.mp4";
plot_path    = "C:\Users\avask\OneDrive\Desktop\Initial Blood Pressure Testing\Plots";
trace_folder = "C:\Users\avask\OneDrive\Desktop\Initial Blood Pressure Testing\Traces";
main_path    = 'C:\Users\avask\OneDrive\Desktop\Initial Blood Pressure Testing';


iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path);

%% Batch Running



% Paths that do NOT change
plot_path    = 'D:\SpO2 Validation Pipeline\Plots Parish';
trace_folder = 'D:\SpO2 Validation Pipeline\Traces Parish';
main_path    = 'D:\SpO2 Validation Pipeline';

% Root where subject folders live
video_root = "D:\SpO2 Validation Pipeline\Data for Parish Stats";

% Loop over subjects 1–10
for subj = 1:3

    subject_name = sprintf('subject_%d', subj);

    video_path = fullfile( ...
        video_root, ...
        subject_name, ...
        subject_name + ".mp4" ...
    );

    fprintf('\n=== Processing %s ===\n', subject_name);
    fprintf('Video path: %s\n', video_path);

    if ~isfile(video_path)
        warning('Video not found for %s — skipping.', subject_name);
        continue;
    end

    % Run pipeline
    iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path);

end

fprintf('\nAll subjects processed.\n');


%% Batch Running for subject folders that contain trial files
clear; clc;

% Ensure all repo functions (including iPPG_pipeline_v4) are on the path
setup_paths();

% ---------------- Fixed Paths ----------------
base_plot_path   = 'D:\Final Senior Desgn Data\Plots';
base_trace_path  = 'D:\Final Senior Desgn Data\Traces';
main_path        = 'D:\Final Senior Desgn Data\';

video_root       = 'D:\Final Senior Desgn Data\finaldataset';

% ---------------- Find subject folders ----------------
subjectDirs = dir(fullfile(video_root, 'subject_*'));
subjectDirs = subjectDirs([subjectDirs.isdir]);

if isempty(subjectDirs)
    error('No subject folders found in: %s', video_root);
end

% ---------------- Collect all valid trial files ----------------
allFiles = [];

for s = 1:numel(subjectDirs)

    subject_name = subjectDirs(s).name;
    subject_path = fullfile(subjectDirs(s).folder, subject_name);

    aviFiles = dir(fullfile(subject_path, 'subject_*_trial_*.avi'));
    mp4Files = dir(fullfile(subject_path, 'subject_*_trial_*.mp4'));

    subjectFiles = [aviFiles; mp4Files];

    if ~isempty(subjectFiles)
        allFiles = [allFiles; subjectFiles]; %#ok<AGROW>
    end
end

if isempty(allFiles)
    error('No video files found inside subject folders in: %s', video_root);
end

% ---------------- Deduplicate (prefer AVI over MP4) ----------------
fileMap = containers.Map;

for k = 1:numel(allFiles)

    name   = allFiles(k).name;
    folder = allFiles(k).folder;

    tok = regexp(name, '^subject_(\d+)_trial_(\d+)\.(avi|mp4)$', 'tokens', 'once');

    if isempty(tok)
        fprintf('Skipping unmatched file: %s\n', fullfile(folder, name));
        continue;
    end

    subj  = tok{1};
    trial = tok{2};
    ext   = lower(tok{3});

    key = sprintf('%s_%s', subj, trial);

    if isKey(fileMap, key)
        existing = fileMap(key);
        if endsWith(lower(existing.name), '.mp4') && strcmp(ext, 'avi')
            fileMap(key) = allFiles(k);
        end
    else
        fileMap(key) = allFiles(k);
    end
end

videoList = values(fileMap);

if isempty(videoList)
    error('Files were found, but none matched subject_X_trial_Y.avi or .mp4');
end

% ---------------- Sort by subject, then trial ----------------
sortKeys = zeros(numel(videoList), 2);

for k = 1:numel(videoList)
    name = videoList{k}.name;
    tok = regexp(name, '^subject_(\d+)_trial_(\d+)\.(avi|mp4)$', 'tokens', 'once');
    sortKeys(k,1) = str2double(tok{1});
    sortKeys(k,2) = str2double(tok{2});
end

[~, idx] = sortrows(sortKeys, [1 2]);
videoList = videoList(idx);

% ---------------- Main Loop ----------------
for k = 1:numel(videoList)

    fileStruct = videoList{k};
    name       = fileStruct.name;
    folder     = fileStruct.folder;
    video_path = fullfile(folder, name);

    tok = regexp(name, '^subject_(\d+)_trial_(\d+)\.(avi|mp4)$', 'tokens', 'once');

    subj  = str2double(tok{1});
    trial = str2double(tok{2});
    ext   = lower(tok{3});

    fprintf('\n=== Processing subject_%d trial_%d (%s) ===\n', subj, trial, ext);

    % ---- Make unique output folders for each trial ----
    trial_tag    = sprintf('subject_%d_trial_%d', subj, trial);
    plot_path    = fullfile(base_plot_path, trial_tag);
    trace_folder = fullfile(base_trace_path, trial_tag);

    if ~exist(plot_path, 'dir')
        mkdir(plot_path);
    end

    if ~exist(trace_folder, 'dir')
        mkdir(trace_folder);
    end

    try
        iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path);
        fprintf('Saved outputs for %s\n', trial_tag);

    catch ME
        warning('Failed on %s: %s', name, ME.message);
    end
end

fprintf('\nDone.\n');
%%