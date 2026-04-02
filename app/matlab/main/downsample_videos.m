
clear; clc;

%% -------------------------------------------------------------------------
%  CONFIGURATION — only edit this section
%% -------------------------------------------------------------------------

% Root folder containing subject_1, subject_2 ... subfolders
dataset_root = 'D:\Final Senior Desgn Data\finaldataset';

% Target resolutions [width, height] and label
resolutions = {
    [640,  480], '480p';
    [480,  360], '360p';
    [320,  240], '240p'
};

% Video extensions to search for, in order of preference
vid_exts = {'.avi', '.mp4'};

%% -------------------------------------------------------------------------
%  FIND SUBJECT FOLDERS  (subject_1, subject_2 ... only — no extras)
%% -------------------------------------------------------------------------

if ~isfolder(dataset_root)
    error('dataset_root does not exist: %s', dataset_root);
end

all_dirs     = dir(dataset_root);
all_dirs     = all_dirs([all_dirs.isdir]);
subject_dirs = all_dirs(~cellfun(@isempty, ...
    regexp({all_dirs.name}, '^subject_\d+$', 'once')));

if isempty(subject_dirs)
    error('No subject_X folders found in: %s', dataset_root);
end

fprintf('Found %d subject folders.\n\n', length(subject_dirs));

%% -------------------------------------------------------------------------
%  MAIN LOOP
%% -------------------------------------------------------------------------

for s = 1:length(subject_dirs)

    subj_name   = subject_dirs(s).name;           % e.g. subject_1
    subj_folder = fullfile(dataset_root, subj_name);

    % Find all trial videos inside this subject folder
    vid_files = {};
    for e = 1:length(vid_exts)
        found = dir(fullfile(subj_folder, ['*' vid_exts{e}]));
        for k = 1:length(found)
            vid_files{end+1} = fullfile(subj_folder, found(k).name); 
        end
    end

    if isempty(vid_files)
        fprintf('[SKIP] No videos found in %s\n', subj_name);
        continue;
    end

    fprintf('--- %s (%d videos) ---\n', subj_name, length(vid_files));

    for v = 1:length(vid_files)

        vid_path  = vid_files{v};
        [~, vid_name, ~] = fileparts(vid_path);   % e.g. subject_1_trial_1

        fprintf('  %s\n', vid_name);

        % Read all frames once
        try
            vr       = VideoReader(vid_path);
            native_w = vr.Width;
            native_h = vr.Height;
            fps      = vr.FrameRate;
            frames   = read(vr, [1 Inf]);          % H x W x C x N  uint8
            fprintf('    Native: %dx%d  %.2f fps  %d frames\n', ...
                native_w, native_h, fps, size(frames, 4));
        catch ME
            warning('    Cannot read video: %s', ME.message);
            continue;
        end

        for r = 1:size(resolutions, 1)

            target_w  = resolutions{r, 1}(1);
            target_h  = resolutions{r, 1}(2);
            res_label = resolutions{r, 2};

            % Skip upsampling
            if target_w > native_w || target_h > native_h
                fprintf('    [SKIP] %s — target larger than native\n', res_label);
                continue;
            end

            % Output video name: subject_1_trial_1_480p.avi
            out_vid_name = sprintf('%s_%s', vid_name, res_label);

            % Output folder: <dataset_root>/Resolutions/480p/subject_1/
            out_dir = fullfile(dataset_root, 'Resolutions', res_label, subj_name);
            if ~exist(out_dir, 'dir')
                mkdir(out_dir);
            end

            out_path = fullfile(out_dir, [out_vid_name '.avi']);

            if exist(out_path, 'file')
                fprintf('    [EXISTS] %s\n', out_vid_name);
                continue;
            end

            fprintf('    Writing %s (%dx%d) ... ', out_vid_name, target_w, target_h);

            try
                vw           = VideoWriter(out_path, 'Motion JPEG AVI');
                vw.FrameRate = fps;
                vw.Quality   = 95;
                open(vw);

                for f = 1:size(frames, 4)
                    frame_small = imresize(frames(:, :, :, f), ...
                                           [target_h, target_w], 'bicubic');
                    writeVideo(vw, frame_small);
                end

                close(vw);
                fprintf('done\n');

            catch ME
                warning('failed: %s', ME.message);
                try; close(vw); catch; end
            end
        end
    end

    fprintf('\n');
end

