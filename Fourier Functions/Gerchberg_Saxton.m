%this function will operate the G-S algorithm
%--------------------------------------------------------------------------
function [hologram] = Gerchberg_Saxton(input,target,input_res,lambda,distance,N,iteration_num,filter)   
    E0 = abs(input);
    hologram = input;   
    for i = 1:iteration_num    
        input = E0.*exp(1i*angle(hologram));
        output = AS_forward_filter(input,input_res,lambda,distance,N,filter);
        output = abs(target).*exp(1i*angle(output));
        hologram= AS_backward_filter(output,input_res,lambda,distance,N,filter);
    end
    hologram = exp(1i*angle(hologram));
end