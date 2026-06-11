%this function will recover the zeropaded matrix into origial one
%---------------------------------------------------------------------------
function output = zeropadoff(input,input_elenum)
    N = length(input);
    center = ceil((N+1)/2);
    if mod(input_elenum,2) == 1
        output = input(center-(input_elenum-1)/2:center+(input_elenum-1)/2,center-(input_elenum-1)/2:center+(input_elenum-1)/2);
    else
        output = input(center-input_elenum/2:center-1+input_elenum/2,center-input_elenum/2:center-1+input_elenum/2);
    end
end