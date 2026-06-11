function E_field = Gaussian_beam(lambda0,x,y,sigma,angle)   
    k0 = 2*pi/lambda0;
    [theta,rho] = cart2pol(x,y);   
    E_field = exp(-(rho/sigma).^2).*exp(1i*k0*x*sin(deg2rad(angle)));      
end