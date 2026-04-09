function subject = extract_subject_from_path(path)
% extract_subject_from_path  Returns a unique identifier for the recording.
%
% If the path contains both a subject number AND a trial number
% (e.g. "subject_1_trial_2.mp4") the result is "subject1_trial2".
% If only a subject number is present the result is "subject1" (legacy).

    % Try subject + trial first (e.g. subject_1_trial_2)
    tok = regexp(path, 'subject_?(\d+)[_\-]trial_?(\d+)', 'tokens', 'ignorecase', 'once');
    if ~isempty(tok)
        subject = sprintf('subject%s_trial%s', tok{1}, tok{2});
        return;
    end

    % Fallback: subject only
    tok = regexp(path, 'subject_?(\d+)', 'tokens', 'ignorecase', 'once');
    if ~isempty(tok)
        subject = ['subject', tok{1}];
        return;
    end

    error('Subject ID not found in path: %s', path);
end