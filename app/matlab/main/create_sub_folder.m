function subject_folder = create_sub_folder(plot_path, subject_name)
%The purpose is to make a folder in the "master" folder based on the
%subjects name 

%format folder name 
folder_name = strcat(subject_name);
%define the full path
subject_folder = fullfile(plot_path, folder_name);

%Create the folder

if ~isfolder(subject_folder)
    mkdir(subject_folder);
    %disp(['Created folder: ', subject_folder]);
end


end