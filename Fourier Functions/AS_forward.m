%this function will propagate light in free space by certain distance
%angular spectrum propagation method
%--------------------------------------------------------------------------
function [output] = AS_forward(input,input_res,lambda,distance,N)
    coord = linspace(-N/2,(N/2-1),N);%coordinate after zeropad
    [x,y] = meshgrid(coord,-coord);
    input_size = N*input_res;
    Kfrequency = 1/input_size*lambda;
    kx = x*Kfrequency;
    ky = y*Kfrequency;
    angular_spectrum = fftshift(fft2(ifftshift(input)));
    H = exp(1i*(2*pi*distance/lambda*sqrt(1-kx.^2-ky.^2))); %transfer function
    output = fftshift(ifft2(ifftshift(angular_spectrum.*H)));
end