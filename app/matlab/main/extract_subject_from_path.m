function subject = extract_subject_from_path(path)

    subject_num = regexp(path, 'subject_?(\d+)', 'tokens', 'ignorecase');

    if ~isempty(subject_num)
        subject = ['subject', subject_num{1}{1}];
    else
        error('Subject ID not found in path: %s', path);
    end
end

