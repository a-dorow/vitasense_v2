function repo_root = setup_paths()
% setup_paths - add repository matlab code to MATLAB path (portable)
this_file = mfilename('fullpath');
this_dir  = fileparts(this_file);
% utils -> matlab -> app -> repo_root
repo_root = fileparts(fileparts(fileparts(this_dir)));
addpath(genpath(fullfile(repo_root, 'app', 'matlab')));
end
