function [hr_bpm, spo2_pct] = run_pipeline_on_video(video_path, varargin)
% run_pipeline_on_video - wrapper to call pipeline and optionally write JSON
% Optional args (name/value):
%   'doPopup'   (logical) default false
%   'writeJson' (logical) default false
%   'jsonPath'  (char/string) default: <video_dir>\<video_name>_vitals.json

    setup_paths();

    p = inputParser;
    p.addParameter('doPopup', false, @(x)islogical(x) || isnumeric(x));
    p.addParameter('writeJson', false, @(x)islogical(x) || isnumeric(x));
    p.addParameter('jsonPath', "", @(x)ischar(x) || isstring(x));
    p.parse(varargin{:});

    doPopup   = logical(p.Results.doPopup);
    writeJson = logical(p.Results.writeJson);
    jsonPath  = string(p.Results.jsonPath);

    % Determine repo root from this file location:
    this_file  = mfilename('fullpath');
    this_dir   = fileparts(this_file);

    % Adjust as needed for your structure; keeping your pattern
    repo_root  = fileparts(fileparts(fileparts(this_dir)));

    plot_path    = fullfile(repo_root, "outputs", "figs");
    trace_folder = fullfile(repo_root, "outputs", "logs");
    if ~isfolder(plot_path), mkdir(plot_path); end
    if ~isfolder(trace_folder), mkdir(trace_folder); end

    [hr_bpm, spo2_pct] = iPPG_pipeline_v4(video_path, plot_path, trace_folder, repo_root, doPopup);

    if writeJson
        if strlength(jsonPath) == 0
            [vp, vn] = fileparts(video_path);
            jsonPath = fullfile(vp, string(vn) + "_vitals.json");
        end
        write_vitals_json(jsonPath, hr_bpm, spo2_pct, video_path);
    end
end