%this function will zeropad the matrix to certain number N
%--------------------------------------------------------------------------
function [output] = zeropad(input,N)
    [input_elenum_x,input_elenum_y] = size(input);
    pad_x = N - input_elenum_x;
    if mod(pad_x,2) == 1
        output = padarray(input,[(pad_x-1)/2+1,0],0,'pre');
        output = padarray(output,[(pad_x-1)/2,0],0,'post');
    else
        output = padarray(input,[pad_x/2,0],0,'pre');
        output = padarray(output,[pad_x/2,0],0,'post');
    end
    
    pad_y = N - input_elenum_y;
    if mod(pad_y,2) == 1
        output = padarray(output,[0,(pad_y-1)/2+1],0,'pre');
        output = padarray(output,[0,(pad_y-1)/2],0,'post');
    else
        output = padarray(output,[0,(pad_y)/2],0,'pre');
        output = padarray(output,[0,(pad_y)/2],0,'post');
    end
end