function [X_output,Y_output] = PB(X_input,Y_input,phase_x,phase_y,theta)
    M11 = phase_x.*cos(theta).^2+phase_y.*sin(theta).^2;
    M22 = phase_x.*sin(theta).^2+phase_y.*cos(theta).^2;
    M12 = -phase_x.*sin(theta).*cos(theta)+phase_y.*sin(theta).*cos(theta);
    M21 = M12;
    X_output = M11.*X_input+M12.*Y_input;
    Y_output = M21.*X_input+M22.*Y_input;
end