%this function will create a pulse excitation at certaion position
%-------------------------------------------------------------------------
function excite = pulse(x,y,pulse_D,pulse_pos)
    excite = zeros(length(y),length(x));
    excite(((x-pulse_pos(1)).^2+(y-pulse_pos(2)).^2)<=(pulse_D/2)^2)=1;
end