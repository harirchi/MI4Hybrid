function [y,p_noise,m_noise]=poly_sim(sys,input,ini_cond,pn_bound,...
    mn_bound,input_bound,state_bound,flag)

% This function simulates a (uncertain) polynomial model with a giving 
% input sequence. The system output is the measurement of states (see
% PolyModel.m or UnPolyModel for more information).
%
% Arguments:
%   sys -- a user-defined system class (see PolyModel.m, UnPolyModel.m)
%   input -- input sequence (an n_i-by-T matrix) where n_i is the dimension
%            of input and T is the time horizon
%   ini_cond -- initial condition for polynomial models (an n-by-1 column
%               vector for n states)
%   pn_bound -- an n-D vector specifying the upper bound for process noise
%               where n is the number of states
%   mn_bound -- an n_y-D vector specifying the upper bound for measurement
%               noise where n_y is the number of outputs
%   input_bound -- an n_i-D vector specifying the upper bound for inputs
%                  where n_i is the number of inputs
%   state_bound -- an n-D vector specifying the upper bound for states
%                  where n is the number of states
%   flag -- the simulation will begin with a fixed initial seed for the
%           random number generator if flag is set to 1
% Outputs:
%   y -- output of the system
%   p_noise -- the generated process noise
%   m_noise -- the generated measurement noise
%
% Syntax:
%   [y,p_noise,m_noise]=poly_sim(sys,input);
%   [y,p_noise,m_noise]=poly_sim(sys,input,ini_cond);
%   [y,p_noise,m_noise]=poly_sim(sys,input,ini_cond,pn_bound,mn_bound);
%   [y,p_noise,m_noise]=poly_sim(sys,input,ini_cond,pn_bound,mn_bound,...
%                                 input_bound);
%   [y,p_noise,m_noise]=poly_sim(sys,input,ini_cond,pn_bound,mn_bound,...
%                                 input_bound,state_bound);
%   [y,p_noise,m_noise]=poly_sim(sys,input,ini_cond,pn_bound,mn_bound,...
%                                 input_bound,state_bound,flag);
%
% Author: MI4Hybrid
% Date: Mar 29th, 2016

% Check if the system model is valid for this function.
if(strcmp(sys.mark,'poly')~=1)
    error('The system model must be a polynomial model.');
end

% Obtain model/input information.
num_arg=nargin;
n=size(sys.coeffmat,1); % dimension of state
n_i=size(sys.degmat,2)-n; % dimension of input
n_y=n; % dimension of output (observing states)

% Set up default values if parameters are not specified.
if(num_arg==2)
    ini_cond=zeros(n,1);
    pn_bound=zeros(n,1);
    mn_bound=zeros(n_y,1);
    input_bound=zeros(n_i,1)+inf;
    state_bound=zeros(n,1)+inf;
    flag=0;
elseif(num_arg==3)
    pn_bound=zeros(n,1);
    mn_bound=zeros(n_y,1);
    input_bound=zeros(n_i,1)+inf;
    state_bound=zeros(n,1)+inf;
    flag=0;
elseif(num_arg==5)
    input_bound=zeros(n_i,1)+inf;
    state_bound=zeros(n,1)+inf;
    flag=0;
elseif(num_arg==6)
    state_bound=zeros(n,1)+inf;
    flag=0;
elseif(num_arg==7)
    flag=0;
end

% Set up default values for empty arguments.
if(isempty(ini_cond))
    ini_cond=zeros(n,1);
end
if(isempty(pn_bound))
    pn_bound=zeros(n,1);
end
if(isempty(mn_bound))
    mn_bound=zeros(n_y,1);
end
if(isempty(input_bound))
    input_bound=zeros(n_i,1)+inf;
end
if(isempty(state_bound))
    state_bound=zeros(n,1)+inf;
end
if(isempty(flag))
    flag=0;
end

% Convert scalars to vectors.
if(length(pn_bound)==1&&n>1)
    pn_bound=ones(n,1)*pn_bound;
    warning(['Bound for process noise is a scalar, converted to a '...
        'vector with identical entries.']);
end
if(length(mn_bound)==1&&n_y>1)
    mn_bound=ones(n_y,1)*mn_bound;
    warning(['Bound for measurement noise is a scalar, converted to'...
        ' a vector with identical entries.']);
end
if(length(input_bound)==1&&n_i>1)
    input_bound=ones(n_i,1)*input_bound;
    warning(['Input bound is a scalar, converted to a vector with '...
        'identical entries.']);
end
if(length(state_bound)==1&&n>1)
    state_bound=ones(n,1)*state_bound;
    warning(['State bound is a scalar, converted to a vector with '...
        'identical entries.']);
end

% Check the bounds.
if(length(pn_bound)~=n||~isvector(pn_bound))
    error('The number of bounds for process noise is not correct.');
end
if(length(mn_bound)~=n_y||~isvector(mn_bound))
    error('The number of bounds for measurement noise is not correct.');
end
if(length(input_bound)~=n_i||~isvector(input_bound))
    error('The number of bounds for inputs is not correct.');
end
if(length(state_bound)~=n||~isvector(state_bound))
    error('The number of bounds for states is not correct.');
end

% Check the input.
if(size(input,1)~=n_i)
    error('The input dimension is not correct.');
end
for i=1:n_i
    if(input_bound(i)~=inf)
        if(norm(input(i,:),sys.input_norm(i))>input_bound(i))
            warning(['At least one dimension of the input sequence '...
                'exceeds its bound']);
            break
        end
    end
end
T=size(input,2); % time horizon

% Check the initial condition.
if(length(ini_cond)~=n||~isvector(ini_cond))
    error('The initial condition is not consistent with the model.');
end

% Create process noise.
a=sys.pn_norm;
k=pn_bound;
p_noise=bounded_noise(a,k,T,flag);

% Create measurement noise.
a=sys.mn_norm;
k=mn_bound;
m_noise=bounded_noise(a,k,T);

n_mono=size(sys.coeffmat,2); % number of monomials

% Create Uncertainty matrix.
if(isprop(sys,'d_coeffmat'))
    a=inf;
    for i = 1:n
        for j = 1:n_mono
            unc_coeffmat(i,j)=bounded_noise(a,sys.d_coeffmat(i,j),1);
        end
    end
else
    unc_coeffmat = zeros(n,n_mono);
end

% Calculate the output.

x_trace=zeros(n,T); % pre-allocate memory for states
y=zeros(n_y,T); % pre-allocate memory for outputs
x=ini_cond;
for i=1:T % for time horizon T
    x_trace(:,i)=x;
    y(:,i)=x+sys.Em*m_noise(:,i);
    x_buffer=zeros(n,1);
    for j=1:n % for n states
        for l=1:n_mono % each new state is calculated from n_mono monomials
            mono=1; % each monomial is calculated with n+n_i variables
            for s=1:n
                mono=mono*x(s)^sys.degmat(l,s);
            end
            for s=1:n_i
                mono=mono*input(s,i)^sys.degmat(l,s+n);
            end
            
            x_buffer(j)=x_buffer(j)+sys.coeffmat(j,l)*mono+ ...
                unc_coeffmat(j,l)*mono;
        end 
    end
    x=x_buffer;
end

% Check the states.
for i=1:n
    if(state_bound(i)~=inf)
        if(norm(x_trace(i,1:T),sys.state_norm(i))>state_bound(i))
            warning(['At least one dimension of the state sequence '...
                'exceeds its bound']);
            break
        end
    end
end

end