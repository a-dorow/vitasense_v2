function vitasenserecorderappv4
% Vitasense Recorder app: camera capture + metadata logging (AVI/MP4 toggle)
% After recording finishes, runs your pipeline wrapper on the recorded video.

% Ensure repo paths are available
try
    setup_paths();
catch
    % If setup_paths isn't on path yet, try running it relative to this file
    try
        this_file = mfilename('fullpath');
        this_dir  = fileparts(this_file);                 % ...\app\matlab\recorder
        run(fullfile(this_dir, "..", "setup_paths.m"));   % ...\app\matlab\setup_paths.m
    catch
        % Allow recording to work; pipeline call may fail later.
    end
end

%% ----------- Top level Container ------------

state = struct();
state.camObj = [];
state.writer = [];
state.frameCount = 0;
state.ticStart = [];
state.previewActive = false;
state.rootFolder = defaultRoot();
state.stopflag = false;
state.stopFlag = state.stopflag;
state.lastSubjectNumber = [];
state.lastSubjectID = "";
state.lastExperiment = "";

%% ------- UI --------

ui = struct();
ui.fig = uifigure('Name','Vitasense Recorder','Position', [100 100 860 520]);
ui.fig.CloseRequestFcn = @onClose;

%------Root folder row------

uicontrolRow(@uilabel, 'Text','Root Folder','Position',[20 470 90 22]);
ui.rootPath = uieditfield(ui.fig,'text', 'Position',[115 470 480 24], ...
    'Value', state.rootFolder,'Editable','off');
ui.btnChooseRoot = uibutton(ui.fig,'Text','Choose...' ,'Position',[605 470 80 24], ...
    'ButtonPushedFcn',@onChooseRoot);
ui.btnOpenRoot = uibutton(ui.fig, 'Text','Open','Position',[690 470 60 24], ...
    'ButtonPushedFcn', @(~,~)openfolder(ui.rootPath.Value));

%------Camera and Recording Panel------
ui.camPanel = uipanel(ui.fig,"Title",'Camera and Recording', 'Position', [20 290 420 170]);
uicontrolRow(@uilabel, 'Parent', ui.camPanel,'Text', 'Camera:', 'Position', [10 110 60 22]);
ui.camDropdown = uidropdown(ui.camPanel, 'Position', [80 110 260 24], ...
    'Items', {'(scanning...)'});
ui.camDropdown.ValueChangedFcn = @onselectcamera;

%------Resolution------
uicontrolRow(@uilabel, 'Parent', ui.camPanel, 'Text', 'Resolution:', 'Position', [10 80 70 22]);
ui.resDropdown = uidropdown(ui.camPanel, 'Position', [90 80 250 24], ...
    'Items',{'(none)'},'Value','(none)');
ui.resDropdown.ValueChangedFcn = @onselectresolution;

% FPS
uicontrolRow(@uilabel,'Parent', ui.camPanel, 'Text','FPS:', 'Position',[10 50 40 22]);
ui.fps = uieditfield(ui.camPanel,'numeric','Position', [50 50 60 24], ...
    'Limits',[1 Inf],'Value',30);

% Duration
uicontrolRow(@uilabel, 'Parent', ui.camPanel,'Text', 'Duration (s):', ...
    'Position', [120 50 80 22]);
ui.duration = uieditfield(ui.camPanel,'numeric', 'Position', [205 50 60 24], ...
    'Limits',[1 Inf], 'Value', 20);

% --------- Video Format Selection ---------
uicontrolRow(@uilabel,'Parent',ui.camPanel,'Text','Format:',...
    'Position',[10 20 55 22]);

ui.formatDropdown = uidropdown(ui.camPanel, ...
    'Position',[70 20 170 24], ...
    'Items', {'MP4 (MPEG-4)', ...
              'AVI (Motion JPEG)', ...
              'AVI (Uncompressed)'}, ...
    'Value','MP4 (MPEG-4)');

% Close preview toggle
ui.closePreviewDuringRec = uicheckbox(ui.camPanel, ...
    'Text','Close Preview During Recording', ...
    'Position',[10 0 240 22], ...
    'Value',true);

% Exposure controls
ui.exposure = uieditfield(ui.camPanel,'numeric','Position',[290 20 60 24], ...
    'Value',-6,'Enable','off');
ui.exposureManual = uicheckbox(ui.camPanel,'Text','Manual Exposure', ...
    'Position',[260 0 120 22],'Value',false,'ValueChangedFcn',@onExposureModeToggle);

%------Meta Data------
ui.metapanel = uipanel(ui.fig,'Title','Metadata','Position',[460 290 360 170]);

uicontrolRow(@uilabel,'Parent', ui.metapanel, 'Text', 'Experiment Title:', ...
    'Position', [10 110 110 22]);
ui.experiment = uieditfield(ui.metapanel,'text', ...
    'Position',[125 110 220 24],'Value','test');

uicontrolRow(@uilabel, 'Parent',ui.metapanel, 'Text', 'Age:', ...
    'Position', [10 80 40 22]);
ui.age = uieditfield(ui.metapanel,'numeric','Position', [50 80 50 24], ...
    'Limits',[0 120]);

uicontrolRow(@uilabel, 'Parent', ui.metapanel,'Text','Race:', ...
    'Position', [110 80 40 22]);
ui.race = uidropdown(ui.metapanel,'Position', [150 80 195 24], ...
    'Items',{'Prefer not to say', 'American Indian/Alaska Native', 'Asian', ...
             'Black/African American','Native Hawaiian/Other Pacific Islander', ...
             'White', 'Other'});

uicontrolRow(@uilabel, 'Parent', ui.metapanel, 'Text', 'Gender:', ...
    'Position', [10 50 50 22]);
ui.gender = uidropdown(ui.metapanel,'Position',[65 50 150 24], ...
    'Items', {'Prefer not to say', 'Female', 'Male'});

uicontrolRow(@uilabel, 'Parent', ui.metapanel, 'Text','Notes:', ...
    'Position',[10 20 50 22]);
ui.notes = uieditfield(ui.metapanel,'text','Position', [65 20 280 24]);

%------Controls Panel------
ui.ctrlpanel = uipanel(ui.fig,"Title",'Controls','Position',[20 180 820 90]);

ui.btnrefresh = uibutton(ui.ctrlpanel,'Text','Refresh Camera', ...
    'Position', [10 25 120 30],'ButtonPushedFcn', @refreshcamera);

ui.btnpreview = uibutton(ui.ctrlpanel, 'Text', 'Start Preview', ...
    'Position',[140 25 120 30], 'ButtonPushedFcn', @togglepreview);

ui.btnstart = uibutton(ui.ctrlpanel,'Text','Start Recording', ...
    'Position', [270 25 140 30], 'ButtonPushedFcn', @startrecording, ...
    'BackgroundColor', [0.85 1 0.85]);

ui.btnstop = uibutton(ui.ctrlpanel,'Text','Stop Recording', ...
    'Position', [420 25 140 30],'ButtonPushedFcn',@stoprecording, ...
    'BackgroundColor', [1 0.85 0.85]);

ui.btnopenexp = uibutton(ui.ctrlpanel,'Text','Open Experiment Folder', ...
    'Position', [570 25 160 30],'ButtonPushedFcn',@openexperimentfolder);

ui.redoSameSubject = uicheckbox(ui.ctrlpanel,'Text','Repeat Previous Subject ID', ...
    'Position',[570 55 220 22],'Value',false);

% ---- Pipeline mode + JSON export ----
ui.procModeLabel = uilabel(ui.ctrlpanel,'Text','Pipeline:', ...
    'Position',[10 55 55 22]);

ui.procMode = uidropdown(ui.ctrlpanel, ...
    'Position',[65 55 140 24], ...
    'Items', {'Research', 'Quick Popup'}, ...
    'Value', 'Research');

ui.writeJson = uicheckbox(ui.ctrlpanel, ...
    'Text','Write vitals JSON', ...
    'Position',[215 55 140 22], ...
    'Value', true);

%------Status + console------
ui.status = uilabel(ui.fig,'Position', [20 140 740 22],'Text','Status: Ready');
ui.readout = uitextarea(ui.fig,'Position',[20 20 740 115], 'Editable', 'off');

% Initialize camera list
refreshcamera();

%% ------Nested UI Helpers------

    function uicontrolRow(factoryFcn, varargin)
        args = varargin;
        if ~any(strcmpi(args,'Parent'))
            args = [{'Parent', ui.fig},args];
        end
        factoryFcn(args{:});
    end

    function onChooseRoot(~,~)
        p = uigetdir(ui.rootPath.Value,'Choose Root Folder for Experiments');
        if ischar(p) || (isstring(p) && strlength(p)>0)
            state.rootFolder = char(p);
            ui.rootPath.Value = state.rootFolder;
            logmsg("Root folder set to: " + state.rootFolder);
        end
    end

    function openexperimentfolder(~,~)
        exp = strtrim(ui.experiment.Value);
        if isempty(exp)
            uialert(ui.fig, 'Please enter an Experiment Title', 'Missing Title');
            return;
        end
        folder = experimentfolder(exp);
        if ~isfolder(folder)
            mkdir(folder);
        end
        openfolder(folder)
    end

    function openfolder(p)
        if isfolder(p)
            winopen(p);
        else
            uialert(ui.fig, 'Folder does not exist.', 'Error');
        end
    end

    function refreshcamera(~,~)
        try
            items = webcamlist;
            if isempty(items)
                ui.camDropdown.Items = {'(No cameras found)'};
                ui.camDropdown.Value = '(No cameras found)';
                ui.resDropdown.Items = {'(none)'};
                ui.resDropdown.Value = '(none)';
            else
                ui.camDropdown.Items = items;
                if ~any(strcmp(ui.camDropdown.Value,items))
                    ui.camDropdown.Value = items{1};
                end
                refreshresolutionsforselectedcamera();
            end
            logmsg("Cameras: " + strjoin(items, ' | '))
        catch ME
            ui.camDropdown.Items = {'(error scanning cameras)'};
            ui.camDropdown.Value = '(error scanning cameras)';
            ui.resDropdown.Items = {'(none)'};
            ui.resDropdown.Value = '(none)';
            logErr(ME)
        end
    end

    function refreshresolutionsforselectedcamera()
        try
            items = webcamlist;
            sel = ui.camDropdown.Value;
            if ~any(strcmp(sel,items))
                ui.resDropdown.Items = {'(none)'};
                ui.resDropdown.Value = '(none)';
                return;
            end
            wtmp = webcam(sel);
            avail = {};
            try
                avail = wtmp.AvailableResolutions;
            catch
                try
                    avail = {wtmp.Resolution};
                catch
                    avail = {};
                end
            end
            clear wtmp;

            if ~isempty(avail)
                orig = avail;
                capped = {};
                for k = 1:numel(avail)
                    tokens = regexp(avail{k},'(\d+)\s*x\s*(\d+)','tokens','once');
                    if ~isempty(tokens)
                        w = str2double(tokens{1});
                        h = str2double(tokens{2});
                        if w <= 1920 && h <= 1080
                            capped{end+1} = avail{k}; %#ok<AGROW>
                        end
                    end
                end
                if ~isempty(capped)
                    avail = capped;
                else
                    avail = orig;
                end
            end

            if isempty(avail)
                ui.resDropdown.Items = {'(none)'};
                ui.resDropdown.Value = '(none)';
            else
                ui.resDropdown.Items = avail;
                if ~any(strcmp(ui.resDropdown.Value, avail))
                    ui.resDropdown.Value = avail{1};
                end
            end
        catch
            ui.resDropdown.Items = {'(none)'};
            ui.resDropdown.Value = '(none)';
        end
    end

    function onselectcamera(~,~)
        refreshresolutionsforselectedcamera();
    end

    function onselectresolution(~,~)
        try
            if ~isempty(state.camObj) && isvalidCam(state.camObj)
                val = ui.resDropdown.Value;
                if ~strcmp(val,'(none)')
                    state.camObj.Resolution = val;
                    applyExposureIfNeeded(state.camObj);
                end
            end
        catch ME
            logErr(ME);
            uialert(ui.fig, 'Resolution may not be supported while preview/recording.', ...
                'Resolution Not Applied')
        end
    end

    function togglepreview(~,~)
        try
            if isempty(state.camObj) || ~isvalidCam(state.camObj)
                sel = ui.camDropdown.Value;
                state.camObj = webcam(sel);
                val = ui.resDropdown.Value;
                if ~strcmp(val,'(none)')
                    try
                        state.camObj.Resolution = val;
                    catch
                        disp('Error setting resolution for preview');
                    end
                end
                applyExposureIfNeeded(state.camObj);
            end
            if ~state.previewActive
                applyExposureIfNeeded(state.camObj);
                preview(state.camObj);
                state.previewActive = true;
                ui.btnpreview.Text = 'Stop Preview';
                logmsg("Preview started at " + string(state.camObj.Resolution));
            else
                closePreview(state.camObj);
                state.previewActive = false;
                ui.btnpreview.Text = 'Start Preview';
                logmsg("Preview stopped.")
            end
        catch ME
            logErr(ME)
        end
    end

%% ------ Recording Lifecycle ------
    function startrecording(~,~)
        exp = strtrim(ui.experiment.Value);
        if isempty(exp)
            uialert(ui.fig, 'Please enter an Experiment Title','Missing Title');
            return;
        end

        fps = ui.fps.Value;
        if ~isfinite(fps) || fps < 1
            uialert(ui.fig, 'FPS must be >= 1', 'Invalid FPS')
            return;
        end

        dur = ui.duration.Value;
        if ~isfinite(dur) || dur < 1
            uialert(ui.fig, 'Duration must be >= 1', 'Invalid Duration')
            return;
        end

        expfolder = experimentfolder(exp);
        if ~isfolder(expfolder)
            mkdir(expfolder);
        end

        if ui.redoSameSubject.Value && ~isempty(state.lastSubjectNumber) && strcmp(state.lastExperiment,exp)
            subN = state.lastSubjectNumber;
        else
            subN = nextsubjectnumber(expfolder);
        end
        subid = sprintf('subject_%d', subN);

        subfolder = fullfile(expfolder,subid);
        if ~isfolder(subfolder)
            mkdir(subfolder)
        end

        % -------- Determine format/profile/extension --------
        formatChoice = ui.formatDropdown.Value;
        switch formatChoice
            case 'MP4 (MPEG-4)'
                ext = '.mp4';
                profile = 'MPEG-4';
            case 'AVI (Motion JPEG)'
                ext = '.avi';
                profile = 'Motion JPEG AVI';
            case 'AVI (Uncompressed)'
                ext = '.avi';
                profile = 'Uncompressed AVI';
            otherwise
                uialert(ui.fig,'Unknown format selected.','Format Error');
                return;
        end

        filepath = fullfile(subfolder, sprintf('%s%s', subid, ext));

        % open camera
        try
            if isempty(state.camObj) || ~isvalidCam(state.camObj)
                sel = ui.camDropdown.Value;
                state.camObj = webcam(sel);
            end

            val = ui.resDropdown.Value;
            if ~strcmp(val,'(none)')
                try
                    state.camObj.Resolution = val;
                catch
                    disp('Error setting resolution for recording');
                end
            end
            applyExposureIfNeeded(state.camObj);
        catch ME
            logErr(ME);
            uialert(ui.fig, 'Unable to open camera.', 'Camera Error');
            return;
        end

        if ui.closePreviewDuringRec.Value && state.previewActive
            try
                closePreview(state.camObj);
                state.previewActive = false;
                ui.btnpreview.Text = 'Start Preview';
                logmsg("Preview closed automatically for recording.");
            catch ME
                logErr(ME);
            end
        end

        % open writer
        try
            state.writer = VideoWriter(filepath, profile);
            state.writer.FrameRate = fps;
            open(state.writer)
        catch ME
            logErr(ME);
            uialert(ui.fig,'Could not create video writer.','Video Error');
            return;
        end

        % capture loop
        try
            period = 1/fps;
            nframes = round(dur * fps);
            state.frameCount = 0;
            state.stopFlag   = false;
            state.stopflag   = state.stopFlag;
            state.ticStart   = tic;

            setRunUIEnabled(false);
            ui.status.Text = sprintf('Status: Recording %s for %ds at %.2f FPS... ', subid, dur, fps);
            logmsg("Recording started " + string(filepath));

            t0      = tic;
            next_t  = 0.0;
            last_ui = -Inf;

            while (state.frameCount < nframes) && ~state.stopFlag
                now_t = toc(t0);

                if now_t + 0.001 >= next_t
                    try
                        img = snapshot(state.camObj);
                        writeVideo(state.writer, img);
                        state.frameCount = state.frameCount + 1;
                    catch ME
                        logErr(ME);
                        break;
                    end

                    next_t = next_t + period;
                    now_t  = toc(t0);

                    if now_t - next_t > 0
                        missed = ceil((now_t - next_t)/period);
                        next_t = next_t + missed*period;
                    end
                else
                    pause(min(0.01, max(0, next_t - now_t)));
                end

                if now_t >= (dur + 1.0)
                    break;
                end

                if now_t - last_ui >= 1.0
                    elapsed = toc(state.ticStart);
                    ui.status.Text = sprintf('Status: Recording... %d/%d frames (%.1fs)', ...
                        state.frameCount, nframes, elapsed);
                    drawnow limitrate;
                    last_ui = now_t;
                end
            end

            % finalize
            try
                elapsed   = toc(state.ticStart);
                actualfps = state.frameCount / max(0.001, elapsed);
            catch
                actualfps = NaN;
            end

            safeCloseWriter(state.writer);
            state.writer = [];

            % log metadata
            try
                info_row = table( ...
                    string(datetime("now","Format",'yyyy-MM-dd HH:mm:ss')), ...
                    string(exp), ...
                    string(subid), ...
                    doubleorNaN(ui.age.Value), ...
                    string(ui.race.Value), ...
                    string(ui.gender.Value), ...
                    string(state.camObj.Name), ...
                    string(getresolutionsafe(state.camObj)), ...
                    double(ui.fps.Value), ...
                    double(actualfps), ...
                    double(ui.duration.Value), ...
                    string(filepath), ...
                    string(profile), ...
                    NaN, ...
                    string(ui.notes.Value), ...
                    'VariableNames', ...
                    {'timestamp','experiment','subject_id','age','race','gender', ...
                     'camera','resolution','target_fps','actual_fps','duration_s', ...
                     'file_path','compression','quality','notes'} );

                appendCSV(expfolder, info_row);
                logmsg("Logged to CSV. Actual FPS: " + sprintf('%.2f', actualfps));
                ui.status.Text = 'Status: Done. Running pipeline...';
            catch ME
                logErr(ME);
                ui.status.Text = 'Status: Done (log write failed). Running pipeline...';
            end

            state.lastSubjectNumber = subN;
            state.lastSubjectID     = subid;
            state.lastExperiment    = exp;

            % call pipeline wrapper (mode + optional JSON export)
            try
                logmsg("Calling run_pipeline_on_video on: " + string(filepath));

                if exist('run_pipeline_on_video','file') ~= 2
                    error("Missing run_pipeline_on_video.m on path.");
                end

                doPopup   = strcmpi(string(ui.procMode.Value), "Quick Popup");
                writeJson = logical(ui.writeJson.Value);

                % Deterministic JSON output path (next to video)
                [vp, vn] = fileparts(filepath);
                jsonPath = fullfile(vp, string(vn) + "_vitals.json");

                [hr_bpm, spo2_pct] = run_pipeline_on_video(filepath, ...
                    'doPopup',   doPopup, ...
                    'writeJson', writeJson, ...
                    'jsonPath',  jsonPath);

                if writeJson
                    logmsg("Wrote JSON: " + string(jsonPath));
                end

                logmsg(sprintf("Pipeline results -> HR: %.2f bpm | SpO2: %.2f %%", hr_bpm, spo2_pct));
                ui.status.Text = 'Status: Done. Pipeline finished.';
            catch ME
                logErr(ME);
                ui.status.Text = 'Status: Done (pipeline error).';
            end

            setRunUIEnabled(true);

        catch ME
            logErr(ME);
            safeCloseWriter(state.writer);
            state.writer = [];
            setRunUIEnabled(true);
        end

        function setRunUIEnabled(tf)
            ui.btnrefresh.Enable      = onOff(tf);
            ui.camDropdown.Enable     = onOff(tf);
            ui.resDropdown.Enable     = onOff(tf);
            ui.btnpreview.Enable      = onOff(tf);
            ui.btnstart.Enable        = onOff(tf);
            ui.btnstop.Enable         = onOff(~tf);
            ui.fps.Enable             = onOff(tf);
            ui.duration.Enable        = onOff(tf);
            ui.experiment.Enable      = onOff(tf);
            ui.age.Enable             = onOff(tf);
            ui.race.Enable            = onOff(tf);
            ui.gender.Enable          = onOff(tf);
            ui.notes.Enable           = onOff(tf);
            ui.btnopenexp.Enable      = onOff(tf);
            ui.redoSameSubject.Enable = onOff(tf);
            ui.formatDropdown.Enable  = onOff(tf);
            ui.closePreviewDuringRec.Enable = onOff(tf);
            ui.exposure.Enable        = onOff(tf && ui.exposureManual.Value);
            ui.exposureManual.Enable  = onOff(tf);

            % new controls
            ui.procMode.Enable        = onOff(tf);
            ui.writeJson.Enable       = onOff(tf);
        end
    end

    function stoprecording(~,~)
        state.stopFlag = true;
        state.stopflag = state.stopFlag;
        logmsg("Stop Requested...");
    end

%% ------------- File/Folder Helpers -----------
    function f = experimentfolder(exptitle)
        safe = regexprep(lower(strtrim(exptitle)),'[^a-z0-9_\- ]','');
        safe = strrep(safe, ' ','_');
        if isempty(safe)
            safe = 'untitled';
        end
        f = fullfile(state.rootFolder, safe);
    end

    function n = nextsubjectnumber(expfolder)
        logpath = fullfile(expfolder,'log.csv');
        n = 1;
        if isfile(logpath)
            try
                T = readtable(logpath);
                if any(strcmpi(T.Properties.VariableNames,'subject_id'))
                    ids  = string(T.subject_id);
                    mask = startsWith(ids,"subject_");
                    Ns = double(erase(ids(mask),"subject_"));
                    Ns   = Ns(~isnan(Ns));
                    if ~isempty(Ns)
                        n = max(Ns) + 1;
                    end
                end
            catch
            end
        end
    end

    function appendCSV(expfolder,row)
        logpath = fullfile(expfolder,'log.csv');
        if isfile(logpath)
            try
                T = readtable(logpath);
                T = [T; row];
                writetable(T, logpath);
            catch
                writetable(row, logpath, 'WriteMode', 'append');
            end
        else
            writetable(row, logpath)
        end
    end

    function s = defaultRoot()
        % Prefer repo-local data/raw if possible (portable default)
        try
            this_file = mfilename('fullpath');    % ...\app\matlab\recorder\...
            this_dir  = fileparts(this_file);
            repo_root = fileparts(fileparts(fileparts(this_dir))); % recorder->matlab->app->repo
            repo_data = fullfile(repo_root, 'data', 'raw');
            if ~isfolder(repo_data), mkdir(repo_data); end
            s = repo_data;
            return;
        catch
        end

        home = char(java.lang.System.getProperty('user.home'));
        candidates = { fullfile(home,'Desktop','Data_for_iPPG'), ...
                       fullfile(pwd,'Data_for_iPPG') };
        for i = 1:numel(candidates)
            try
                if ~isfolder(candidates{i})
                    mkdir(candidates{i});
                end
                s = candidates{i};
                return;
            catch
            end
        end
        s = pwd;
    end

%%---- Small helpers -----
    function tf = isvalidCam(c)
        tf = ~isempty(c);
        if tf
            try
                tf = isvalid(c);
            catch
                tf = false;
            end
        end
    end

    function res = getresolutionsafe(c)
        try
            res = c.Resolution;
        catch
            res = "";
        end
    end

    function out = onOff(tf)
        out = tern(tf, 'on', 'off');
    end

    function r = tern(cond,a,b)
        if cond
            r = a;
        else
            r = b;
        end
    end

    function x = doubleorNaN(val)
        if isempty(val) || ~isfinite(val)
            x = NaN;
        else
            x = double(val);
        end
    end

    function logmsg(s)
        ui.readout.Value = [ui.readout.Value; string(s)];
        drawnow limitrate;
    end

    function logErr(ME)
        ui.readout.Value = [ui.readout.Value; "ERROR: " + string(ME.message)];
        disp(getReport(ME))
    end

    function onExposureModeToggle(~,~)
        ui.exposure.Enable = onOff(ui.exposureManual.Value);
        if ~isempty(state.camObj) && isvalidCam(state.camObj)
            applyExposureIfNeeded(state.camObj);
        end
    end

    function applyExposureIfNeeded(c)
        if isempty(c) || ~isvalidCam(c)
            return;
        end
        if ui.exposureManual.Value
            try
                if isprop(c,'ExposureMode')
                    c.ExposureMode = 'manual';
                end
            catch
            end
            try
                if isprop(c,'Exposure')
                    c.Exposure = ui.exposure.Value;
                end
            catch
            end
        else
            try
                if isprop(c,'ExposureMode')
                    c.ExposureMode = 'auto';
                end
            catch
            end
        end
    end

    function safeCloseWriter(w)
        try
            if ~isempty(w) && isa(w,'VideoWriter')
                if isopen(w)
                    close(w);
                end
            end
        catch
        end
    end

%%---- Close handler -----
    function onClose(~,~)
        try
            if ~isempty(state.camObj) && isvalidCam(state.camObj)
                if state.previewActive
                    closePreview(state.camObj);
                end
                clear state.camObj
            end
        catch
        end
        try
            safeCloseWriter(state.writer);
            state.writer = [];
        catch
        end
        delete(ui.fig);
    end

end