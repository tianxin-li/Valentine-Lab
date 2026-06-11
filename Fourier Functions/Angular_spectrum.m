%this function will calculate the angular spectrum of certain field
%angular spectrum propagation method
%--------------------------------------------------------------------------
function [spectrum,kx,ky] = Angular_spectrum(input,input_res,lambda,N)
    coord = linspace(-N/2,(N/2-1),N);%coordinate after zeropad
    [x,y] = meshgrid(coord,-coord);
    input_size = N*input_res;
    Kfrequency = 1/input_size*lambda;
    kx = x*Kfrequency;
    ky = y*Kfrequency;
    spectrum = fftshift(fft2(ifftshift(input)))/N;
end