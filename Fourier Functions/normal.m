%this function will normalize E2 to E1
%--------------------------------------------------------------------------
function [output1,output2] = normal(input1,input2)
    int_input1 = sum(abs(input1).^2,'all');
    int_input2 = sum(abs(input2).^2,'all');
    norm = int_input1/int_input2;
    output1 = input1;
    output2 = sqrt(norm)*input2;
end