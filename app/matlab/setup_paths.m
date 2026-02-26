function repo_root = setup_paths()
%Adds the repo NATLAB code to the path based on file location. 

dis_file = mfilename("fullpath");  % ...\app\matlab\setup_paths.m
dis_dir = fileparts(dis_file);  % ...\app\matlab

% where art thou file root
repo_root = fileparts(fileparts(dis_dir));

% Add only the matlab treeeeeeeee
addpath(genpath(fullfile(repo_root, 'app', 'matlab')))

end
