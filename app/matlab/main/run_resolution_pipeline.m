%% run_resolution_pipeline.m
% Runs iPPG_pipeline_v4 on every resolution folder produced by downsample_videos.m.


clear; clc;

%% -------------------------------------------------------------------------
%  CONFIGURATION — must match dataset_root in downsample_videos.m
%% -------------------------------------------------------------------------

dataset_root = 'D:\Final Senior Desgn Data\finaldataset';

resolutions  = {'480p', '360p', '240p'};

%% -------------------------------------------------------------------------
%  LOOP — one pipeline run per resolution
%% -------------------------------------------------------------------------

for r = 1:length(resolutions)

    res_label    = resolutions{r};
    video_root   = fullfile(dataset_root, 'Resolutions', res_label);
    plot_path    = fullfile(dataset_root, 'Resolutions', res_label, 'Plots');
    trace_folder = fullfile(dataset_root, 'Resolutions', res_label, 'Traces');
    main_path    = fullfile(dataset_root, 'Resolutions', res_label);

    if ~isfolder(video_root)
        fprintf('[SKIP] %s — folder not found: %s\n', res_label, video_root);
        continue;
    end

    fprintf('\n========================================\n');
    fprintf('Resolution: %s\n', res_label);
    fprintf('  video_root   : %s\n', video_root);
    fprintf('  plot_path    : %s\n', plot_path);
    fprintf('  trace_folder : %s\n', trace_folder);
    fprintf('========================================\n');

    try
        iPPG_pipeline_v4(video_root, plot_path, trace_folder, main_path);
        fprintf('[DONE] %s\n', res_label);
    catch ME
        warning('[FAILED] %s: %s', res_label, ME.message);
    end

end

fprintf('\nAll resolution runs complete.\n');
fprintf('Now run aggregate_resolution_results.m to build the summary table.\n');