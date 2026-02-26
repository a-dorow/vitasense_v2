function selected_method = select_extraction_method(method_name, ippgSettings)
    % Ensure the method_name exists within ippgSettings.EXTRACTION
    if isfield(ippgSettings.EXTRACTION, method_name)
        selected_method = ippgSettings.EXTRACTION.(method_name);
    else
        error(['Method ', method_name, ' is not defined in ippgSettings.EXTRACTION.']);
    end
end
