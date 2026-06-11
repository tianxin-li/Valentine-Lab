%this function will backward propagate light in free space by certain distance
%angular spectrum propagation method
%--------------------------------------------------------------------------
function [input] = AS_backward(output,input_res,lambda,distance,N)
    coord = linspace(-N/2,(N/2-1),N);%coordinate after zeropad
    [x,y] = meshgrid(coord,-coord);
    input_size = N*input_res;
    Kfrequency = 1/input_size*lambda;
    kx = x*Kfrequency;
    ky = y*Kfrequency;
    field_stop = aperture(kx,ky,1);
    angular_spectrum = fftshift(fft2(ifftshift(output)))/N;
    H = exp(-1i*(2*pi*distance/lambda*sqrt(1-kx.^2-ky.^2).*field_stop)).*field_stop; %transfer function 
    input = fftshift(ifft2(ifftshift(angular_spectrum.*H*N)));
end
