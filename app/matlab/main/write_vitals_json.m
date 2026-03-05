function write_vitals_json(jsonPath, hr_bpm, spo2_pct, video_path, bp_struct)
% write_vitals_json - write vitals (and optional BP) to a JSON file.
%
% Usage:
%   write_vitals_json(jsonPath, hr_bpm, spo2_pct, video_path)
%   write_vitals_json(jsonPath, hr_bpm, spo2_pct, video_path, bp_struct)
%
% bp_struct (optional) can include fields like:
%   bp_struct.sbp_mean, bp_struct.dbp_mean, bp_struct.sbp_std, bp_struct.dbp_std

    if nargin < 4
        error('write_vitals_json requires jsonPath, hr_bpm, spo2_pct, video_path.');
    end
    if nargin < 5
        bp_struct = struct();
    end

    % Normalize types
    jsonPath  = char(string(jsonPath));
    videoPath = char(string(video_path));

    % Ensure output folder exists
    outDir = fileparts(jsonPath);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    % Build payload
    s = struct();
    s.timestamp_iso = char(datetime('now','TimeZone','local','Format',"yyyy-MM-dd'T'HH:mm:ssXXX"));
    s.video_path    = videoPath;
    s.hr_bpm        = double(hr_bpm);
    s.spo2_pct      = double(spo2_pct);

    % Optional BP fields
    if ~isempty(fieldnames(bp_struct))
        if isfield(bp_struct,'sbp_mean'), s.sbp_mean = double(bp_struct.sbp_mean); end
        if isfield(bp_struct,'dbp_mean'), s.dbp_mean = double(bp_struct.dbp_mean); end
        if isfield(bp_struct,'sbp_std'),  s.sbp_std  = double(bp_struct.sbp_std);  end
        if isfield(bp_struct,'dbp_std'),  s.dbp_std  = double(bp_struct.dbp_std);  end
    end

    % Encode and write
    jsonText = jsonencode(s);

    fid = fopen(jsonPath, 'w');
    if fid < 0
        error('Failed to open JSON for writing: %s', jsonPath);
    end
    fwrite(fid, jsonText, 'char');
    fclose(fid);
end