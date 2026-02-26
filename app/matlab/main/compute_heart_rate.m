function heart_rate = compute_heart_rate(data)
%This function calculates the heart rate from the provided signal data by
%finding the maximum value and multiplying by 60


%Ensure data isn't empty

if isempty(data)
    heart_rate = NaN;
    return;
end

%Finding the max point

max_value = max(data);

%Calculate the heart rate

heart_rate = max_value*60;

end