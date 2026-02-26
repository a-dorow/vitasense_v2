function [] = datacycle(data_folder)
%Cycle through the dataset 

%Validate the data folder
if ~isfolder(data_folder)
    error('Data folder does not exist')
end

%List out the subfolder
subjects = dir(data_folder);
subjects = subjects([subjects.isdir]);
subjects = subjects(~ismember({subjects.name}, {'.', '..', 'desktop.ini'}));

if isempty(subjects)
    disp('No subjects found in the root folder.');
    return;
end

%Run through all directories
    for i = 1:length(subjects)
    subject_name = subjects(i).name;
    subject_folder = fullfile(root_folder, subject_name);
    if subjects(i).isdir
        files = dir(subject_folder);
        files = files (~ismember({files.name},{'.', '..','desktop.ini'}));
    end
    %checking if there was a video

    end


