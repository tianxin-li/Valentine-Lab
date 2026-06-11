%this function will propagate light in free space by certain distance
%transfer function was restricted with certaion filter
%angular spectrum propagation method
%--------------------------------------------------------------------------
function [output] = AS_forward_filter(input,input_res,lambda,distance,N,filter)
    coord = linspace(-N/2,(N/2-1),N);%coordinate after zeropad
    [x,y] = meshgrid(coord,-coord);
    input_size = N*input_res;
    Kfrequency = 1/input_size*lambda;
    kx = x*Kfrequency;
    ky = y*Kfrequency;
    field_stop = aperture(kx,ky,filter);
    angular_spectrum = fftshift(fft2(ifftshift(input)))/N;
    H = exp(1i*(2*pi*distance/lambda*sqrt(1-kx.^2-ky.^2))).*field_stop; %transfer function
    output = fftshift(ifft2(ifftshift(angular_spectrum.*H*N)));
end